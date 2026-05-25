# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Walks an RNG <element> / <define> subtree and accumulates members on
        # a GeneratedClass.
        #
        # Supported constructs:
        #   element, attribute, ref, text, data, value, empty,
        #   optional, zeroOrMore, oneOrMore, group, choice, mixed, list,
        #   interleave
        #
        # Refs are resolved by name against the grammar's defines:
        # - Wrapping (single-element) define -> typed attribute on parent.
        # - Fragment define                  -> `import_model` on parent.
        # - Simple/Union typed define        -> typed attribute (type symbol).
        #
        # Shape classification (define-wraps-data, define-wraps-enum-choice,
        # union) is delegated to DefineClassifier. Value-shape resolution
        # for individual children is delegated to ValueTypeResolver.
        class ElementVisitor
          # RNG child element names this visitor knows how to dispatch.
          DISPATCHABLE_KINDS = %i[
            element attribute ref group optional oneOrMore zeroOrMore
            choice list interleave empty
          ].freeze

          # Per-kind context overrides applied during dispatch for the
          # repeating constructs. Keys not present pass through unchanged.
          REPETITION_CTX = {
            zeroOrMore: { collection: (0..Float::INFINITY), initialize_empty: true },
            oneOrMore: { collection: (1..Float::INFINITY), initialize_empty: true },
            list: { collection: (0..Float::INFINITY), initialize_empty: true },
          }.freeze

          # `kind` symbol -> handler method name. Adding a new construct
          # only needs a new entry plus the handler method.
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

          # Compile a top-level <element>. Always becomes a rooted class.
          def compile_element(element)
            class_name = Utils.camel_case(element.attr_name)
            gen = @classes[class_name] ||= GeneratedClass.new(
              class_name: class_name,
              xml_name: element.attr_name,
              documentation: documentation_text(element),
              namespace_class: @namespace_class,
            )
            visit_content(element, gen)
            gen
          end

          # Compile a <define> into a class.
          # - Define body matches a simple-type shape -> SimpleType/UnionType.
          # - Wraps exactly one element                -> rooted Serializable.
          # - Multiple or zero wrapped elements        -> fragment Serializable.
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

            gen = GeneratedClass.new(
              class_name: class_name,
              xml_name: wrapping ? wrapping.attr_name : define.name,
              fragment: wrapping.nil?,
              documentation: documentation_text(define) || documentation_text(wrapping),
              namespace_class: @namespace_class,
            )
            register_class!(gen)
            visit_content(wrapping || define, gen)
            gen
          end

          def register_class!(klass)
            @classes[klass.class_name] = klass
          end

          # Extracts <documentation>...</documentation> text from an RNG node.
          # Returns a single joined string or nil.
          def documentation_text(node)
            return nil unless node.respond_to?(:documentation)

            docs = Array(node.documentation).map(&:to_s).reject(&:empty?)
            docs.empty? ? nil : docs.join("\n")
          end

          # Generic content walker. `node` is any RNG container (Element,
          # Define, Optional, OneOrMore, ZeroOrMore, Group). Children get
          # turned into attributes/imports on `gen`, with cardinality and
          # optionality propagated through `ctx`.
          #
          # Walks children in original document order using `element_order`
          # (populated by the rng gem's `ordered` XML mapping). Mirrors
          # XmlCompiler's `resolved_element_order` so the XML mappings come
          # out in the same order the schema author wrote them.
          def visit_content(node, gen, ctx = default_ctx)
            ordered_children(node).each do |kind, child|
              dispatch(kind, child, gen, ctx)
            end

            gen.mixed = true if mixed?(node)
            gen.text_content = true if text?(node)
          end

          def default_ctx
            { collection: nil, initialize_empty: false }
          end

          # Return [kind, child] pairs in original document order. Falls back
          # to typed-array iteration if element_order isn't populated for
          # this node (older rng gem versions, or hand-constructed grammars).
          def ordered_children(node)
            element_entries = element_order_entries(node)
            return fallback_each_child_kind(node) if element_entries.empty?

            indices = ::Hash.new(0)
            element_entries.each_with_object([]) do |entry, pairs|
              kind = entry.name.to_sym
              next unless DISPATCHABLE_KINDS.include?(kind) && node.respond_to?(kind)

              child = Array(node.public_send(kind))[indices[kind]]
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

          # All handlers share the uniform signature
          # (kind, child, parent_gen, ctx). Most ignore `kind`; the
          # repetition handler uses it to look up its collection range.
          def dispatch(kind, child, gen, ctx)
            handler = HANDLERS[kind] or return

            send(handler, kind, child, gen, ctx)
          end

          # --- handlers ---------------------------------------------------

          def handle_element(_kind, child, parent_gen, ctx)
            doc = documentation_text(child)
            value_type = @value_type_resolver.resolve(child)
            type = value_type || compile_element(child).class_name
            parent_gen.add_attribute(build_attribute(child, type, :element, ctx, doc))
          end

          def handle_attribute(_kind, child, parent_gen, ctx)
            doc = documentation_text(child)
            value_type = @value_type_resolver.resolve(child) || :string
            fixed = fixed_value_default(child)
            parent_gen.add_attribute(
              build_attribute(child, value_type, :attribute, ctx, doc, default: fixed),
            )
          end

          def build_attribute(child, type, kind, ctx, doc, default: nil)
            Attribute.new(
              name: Utils.snake_case(child.attr_name),
              type: type,
              xml_name: child.attr_name,
              kind: kind,
              collection: ctx[:collection],
              initialize_empty: ctx[:initialize_empty],
              documentation: doc,
              default: default,
            )
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

          def handle_ref(_kind, ref, parent_gen, ctx)
            target_define = @defines[ref.name]
            raise Lutaml::Model::Error, "ref to unknown define: #{ref.name}" unless target_define

            target_class = compile_define(target_define)

            if simple_type?(target_class)
              parent_gen.add_attribute(build_ref_attribute(ref, target_class.type_symbol, ref.name, ctx))
            elsif target_class.fragment && ctx[:collection].nil?
              parent_gen.add_import(target_class.class_name)
            else
              parent_gen.add_attribute(
                build_ref_attribute(ref, target_class.class_name, target_class.xml_name, ctx),
              )
            end
          end

          def simple_type?(klass)
            klass.is_a?(SimpleType) || klass.is_a?(UnionType)
          end

          def build_ref_attribute(ref, type, xml_name, ctx)
            Attribute.new(
              name: Utils.snake_case(ref.name),
              type: type,
              xml_name: xml_name,
              kind: :element,
              collection: ctx[:collection],
              initialize_empty: ctx[:initialize_empty],
            )
          end

          # <group> = ordered sequence of items. Attribute declarations stay
          # flat (matching XmlCompiler); XML mappings wrap in `sequence do
          # ... end` to preserve document order.
          def handle_group(_kind, group, parent_gen, ctx)
            collector = MemberCollector.new
            visit_content(group, collector, ctx)
            seq = Sequence.new
            collector.members.each { |m| seq.add(m) }
            parent_gen.add_sequence(seq) unless seq.members.empty?
          end

          # Optional: attributes are nullable by default in Lutaml::Model, so
          # no cardinality change. Preserve any inherited collection context.
          def handle_optional(_kind, opt, parent_gen, ctx)
            visit_content(opt, parent_gen, ctx)
          end

          # <interleave> = order-independent group. Treated like a flat
          # group; XML order constraints aren't enforced (matches XSD
          # compiler's behavior of treating <xs:all> like <xs:sequence>).
          def handle_interleave(_kind, interleave, parent_gen, ctx)
            visit_content(interleave, parent_gen, ctx)
          end

          # Drives zeroOrMore, oneOrMore, and list — all repeat their inner
          # content with a collection range from REPETITION_CTX.
          def handle_repeating(kind, node, parent_gen, ctx)
            visit_content(node, parent_gen, ctx.merge(REPETITION_CTX.fetch(kind)))
          end

          def handle_choice(_kind, choice, parent_gen, ctx)
            # Pure value-choices (enums) are folded into the parent by
            # ValueTypeResolver. Skip them here.
            return if RngHelpers.pure_value_choice?(choice)

            spec = Choice.new
            collector = MemberCollector.new
            visit_content(choice, collector, ctx)
            collector.members.each { |m| spec.add_alternative(m) }
            parent_gen.add_choice(spec) unless spec.alternatives.empty?
          end

          def handle_empty(_kind, _child, _parent_gen, _ctx)
            # <empty/> contributes no content — intentionally no-op.
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
