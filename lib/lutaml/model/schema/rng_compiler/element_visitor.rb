# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Walks an RNG <element> / <define> subtree and produces
        # Definitions::Model / Definitions::RestrictedType / Definitions::UnionType
        # objects, registered in the shared `classes` hash.
        #
        # Supported constructs:
        #   element, attribute, ref, text, data, value, empty,
        #   optional, zeroOrMore, oneOrMore, group, choice, mixed, list,
        #   interleave
        #
        # Shape classification (define-wraps-data, define-wraps-enum-choice,
        # union) is delegated to DefineClassifier. Value-shape resolution
        # for individual children is delegated to ValueTypeResolver.
        class ElementVisitor
          DISPATCHABLE_KINDS = %i[
            element attribute ref group optional oneOrMore zeroOrMore
            choice list interleave empty
          ].freeze

          REPETITION_CTX = {
            zeroOrMore: { collection: (0..Float::INFINITY), initialize_empty: true },
            oneOrMore: { collection: (1..Float::INFINITY), initialize_empty: true },
            list: { collection: (0..Float::INFINITY), initialize_empty: true },
          }.freeze

          HANDLERS = {
            element: :handle_element,
            attribute: :handle_attribute,
            ref: :handle_ref,
            group: :handle_group,
            optional: :handle_optional,
            oneOrMore: :handle_repeating,
            zeroOrMore: :handle_repeating,
            list: :handle_repeating,
            choice: :handle_choice,
            interleave: :handle_interleave,
            empty: :handle_empty,
          }.freeze

          def initialize(defines, classes, namespace_class: nil)
            @defines = defines
            @classes = classes
            @namespace_class = namespace_class
            @value_type_resolver = ValueTypeResolver.new(
              defines, classes,
              compile_define: method(:compile_define),
              register_class: method(:register_class!)
            )
          end

          # Compile a top-level <element>. Always becomes a rooted model.
          def compile_element(element)
            class_name = Utils.camel_case(element.attr_name)
            model = @classes[class_name] ||= Definitions::Model.new(
              class_name: class_name,
              xml_root: Definitions::XmlRoot.new(kind: :element, name: element.attr_name),
              documentation: documentation_text(element),
              namespace_class_name: @namespace_class,
            )
            visit_content(element, model)
            model
          end

          # Compile a <define> into a class.
          # - Define body matches a simple-type shape -> RestrictedType/UnionType.
          # - Wraps exactly one element                -> rooted Definitions::Model.
          # - Multiple or zero wrapped elements        -> fragment Definitions::Model.
          def compile_define(define)
            class_name = Utils.camel_case(define.name)
            return @classes[class_name] if @classes.key?(class_name)

            if (simple = DefineClassifier.build(define, class_name))
              register_class!(simple)
              return simple
            end

            build_complex_define(define, class_name)
          end

          private

          def build_complex_define(define, class_name)
            wrapping = define.element.size == 1 ? define.element.first : nil

            xml_root = if wrapping
                         Definitions::XmlRoot.new(kind: :element, name: wrapping.attr_name)
                       else
                         Definitions::XmlRoot.new(kind: :fragment)
                       end

            model = Definitions::Model.new(
              class_name: class_name,
              xml_root: xml_root,
              documentation: documentation_text(define) || documentation_text(wrapping),
              namespace_class_name: @namespace_class,
            )
            register_class!(model)
            visit_content(wrapping || define, model)
            model
          end

          def register_class!(klass)
            @classes[klass.class_name] = klass
          end

          def documentation_text(node)
            return nil unless node.respond_to?(:documentation)

            docs = Array(node.documentation).map(&:to_s).reject(&:empty?)
            docs.empty? ? nil : docs.join("\n")
          end

          # Generic content walker.
          def visit_content(node, model, ctx = default_ctx)
            ordered_children(node).each do |kind, child|
              dispatch(kind, child, model, ctx)
            end

            model.mixed = true if mixed?(node)
            model.text_content = true if text?(node)
          end

          def default_ctx
            { collection: nil, initialize_empty: false }
          end

          def ordered_children(node)
            element_entries = element_order_entries(node)
            return fallback_each_child_kind(node) if element_entries.empty?

            arrays = {}
            indices = ::Hash.new(0)
            element_entries.each_with_object([]) do |entry, pairs|
              kind = entry.name.to_sym
              next unless DISPATCHABLE_KINDS.include?(kind) && node.respond_to?(kind)

              children = arrays[kind] ||= Array(node.public_send(kind))
              child = children[indices[kind]]
              indices[kind] += 1
              pairs << [kind, child] if child
            end
          end

          def element_order_entries(node)
            return [] unless node.respond_to?(:element_order)

            Array(node.element_order).select do |e|
              e.respond_to?(:node_type) && e.node_type == :element
            end
          end

          def fallback_each_child_kind(node)
            DISPATCHABLE_KINDS.each_with_object([]) do |attr_name, pairs|
              next unless node.respond_to?(attr_name)

              Array(node.public_send(attr_name)).each do |child|
                pairs << [attr_name, child] unless child.nil?
              end
            end
          end

          def dispatch(kind, child, parent, ctx)
            handler = HANDLERS[kind] or return

            send(handler, kind, child, parent, ctx)
          end

          # --- handlers ---------------------------------------------------

          def handle_element(_kind, child, parent, ctx)
            doc = documentation_text(child)
            value_type = @value_type_resolver.resolve(child)
            type_ref = type_ref_for_element(child, value_type)
            push_attribute(parent, build_attribute(child, type_ref, :element, ctx, doc))
          end

          def type_ref_for_element(child, value_type)
            return Definitions::TypeRef.new(kind: :symbol, value: value_type.to_s) if value_type

            compiled = compile_element(child)
            Definitions::TypeRef.new(kind: :class_ref, value: compiled.class_name)
          end

          def handle_attribute(_kind, child, parent, ctx)
            doc = documentation_text(child)
            symbol = @value_type_resolver.resolve(child) || :string
            type_ref = Definitions::TypeRef.new(kind: :symbol, value: symbol.to_s)
            fixed = fixed_value_default(child)
            push_attribute(parent, build_attribute(child, type_ref, :attribute, ctx, doc, default: fixed))
          end

          def build_attribute(child, type_ref, kind, ctx, doc, default: nil)
            xml_name = xml_name_for(child)
            Definitions::Attribute.new(
              name: Utils.snake_case(xml_name.tr(":", "_")),
              type: type_ref,
              xml_name: xml_name,
              kind: kind,
              collection: ctx[:collection] || false,
              initialize_empty: ctx[:initialize_empty] || false,
              documentation: doc,
              default: default,
            )
          end

          def xml_name_for(child)
            name = child.attr_name
            ns = child.respond_to?(:ns) ? child.ns : nil
            return name unless ns == "xml"

            "#{ns}:#{name}"
          end

          # <attribute name="x"><value>X</value></attribute> = fixed value.
          # Match XSD compiler's behavior — emit `default: -> { "X" }` so
          # the value round-trips even when omitted.
          def fixed_value_default(container)
            return nil unless container.respond_to?(:value)

            values = Array(container.value)
            return nil if values.size != 1
            return nil if RngHelpers.structural_content?(container)

            values.first.value.to_s
          end

          def handle_ref(_kind, ref, parent, ctx)
            target_define = @defines[ref.name]
            raise Lutaml::Model::Error, "ref to unknown define: #{ref.name}" unless target_define

            target_class = compile_define(target_define)

            if RngHelpers.simple_type?(target_class)
              type_ref = Definitions::TypeRef.new(kind: :symbol, value: RngHelpers.type_symbol(target_class.class_name).to_s)
              push_attribute(parent, build_ref_attribute(ref, type_ref, ref.name, ctx))
            elsif RngHelpers.fragment_model?(target_class) && ctx[:collection].nil?
              push_import(parent, target_class.class_name)
            else
              type_ref = Definitions::TypeRef.new(kind: :class_ref, value: target_class.class_name)
              xml_name = target_class.xml_root.name || ref.name
              push_attribute(parent, build_ref_attribute(ref, type_ref, xml_name, ctx))
            end
          end

          def build_ref_attribute(ref, type_ref, xml_name, ctx)
            Definitions::Attribute.new(
              name: Utils.snake_case(ref.name),
              type: type_ref,
              xml_name: xml_name,
              kind: :element,
              collection: ctx[:collection] || false,
              initialize_empty: ctx[:initialize_empty] || false,
            )
          end

          # <group> = ordered sequence of items.
          def handle_group(_kind, group, parent, ctx)
            collector = MemberCollector.new
            visit_content(group, collector, ctx)
            return if collector.members.empty?

            parent.members << Definitions::Sequence.new(members: collector.members)
            collector.imports.each { |name| push_import(parent, name) }
          end

          def handle_optional(_kind, opt, parent, ctx)
            visit_content(opt, parent, ctx)
          end

          def handle_interleave(_kind, interleave, parent, ctx)
            visit_content(interleave, parent, ctx)
          end

          def handle_repeating(kind, node, parent, ctx)
            visit_content(node, parent, ctx.merge(REPETITION_CTX.fetch(kind)))
          end

          def handle_choice(_kind, choice, parent, ctx)
            return if RngHelpers.pure_value_choice?(choice)

            collector = MemberCollector.new
            visit_content(choice, collector, ctx)
            return if collector.members.empty?

            parent.members << Definitions::Choice.new(
              alternatives: collector.members,
              header: "choice",
            )
            collector.imports.each { |name| push_import(parent, name) }
          end

          def handle_empty(_kind, _child, _parent, _ctx)
            # <empty/> contributes no content — intentionally no-op.
          end

          def push_attribute(parent, attr)
            parent.members.reject! do |m|
              m.is_a?(Definitions::Attribute) && m.name == attr.name
            end
            parent.members << attr
          end

          def push_import(parent, name)
            parent.imports << name unless parent.imports.include?(name)
          end

          def mixed?(node)
            node.respond_to?(:mixed) && Utils.present?(node.mixed)
          end

          def text?(node)
            node.respond_to?(:text) && Utils.present?(node.text)
          end
        end
      end
    end
  end
end
