# frozen_string_literal: true

module Lutaml
  module Xml
    module Leptris
      # Serialize-side mirror of the plan fast path: builds the output
      # tree directly through leptris's fused create_child chain — no
      # XmlElement tree, no DeclarationPlanner pass, no builder context
      # stack, no moxml wrapper minting. Serialized shapes must be the
      # plain ones (attributes, scalars, collections, nested models,
      # raw fragments, content runs); custom-method, polymorphic,
      # union, and multi-spelling rows keep the interpretive serializer
      # (their output flows through hash-shaped custom APIs).
      #
      # Ordered/mixed models serialize from element_order when the
      # instance carries one (parsed models): text runs, comments, and
      # element entries in document order, mirroring the interpretive
      # order applier — including its content-attr-first text reads
      # (mutations to the model show up) and CDATA flattening. Models
      # without element_order fall back interpretively (return nil).
      module PlanSerializer
        SERIALIZABLE_KINDS = %i[scalar collection_native collection_cb
                                nested ordered_deferred raw content
                                content_deferred].freeze
        CONTENT_KINDS = %i[content content_deferred].freeze

        class << self
          # plan: the compiler's entry for instance's class
          def call(instance, plan, register = nil)
            # The child model's declared lutaml_default_register takes
            # precedence over the ambient register — the resolve_for_child
            # contract (#876); without it, child plans and attribute
            # serialization resolve in the parent context.
            register = Lutaml::Model::Register.resolve_for_child(
              instance.class,
              register || Lutaml::Model::Config.default_register,
            )
            return nil if plan[:ordered] && instance.element_order.nil?

            doc = ::Leptris::XML::Document.create
            ns_ctx = Namespaces.new(plan)
            return nil if ns_ctx.unspellable?

            root = doc.create_element(
              ns_ctx.spell(plan[:tree][:name], plan[:tree][:ns]),
            )
            doc.root = root
            ns_ctx.declare_on(root, plan[:tree][:attr_form])
            if plan[:ordered]
              build_ordered(root, instance, plan, doc, register)
            else
              build(root, instance, plan, doc, register, ns_ctx)
            end
            doc.to_xml(indent: 2, no_decl: true)
          end

          # Namespace spelling for namespaced plans (#847): every ns
          # form resolves to a wire spelling (prefix:local, or local
          # under a default xmlns), and every distinct (prefix, uri)
          # pair is declared exactly once on the output root in
          # first-encounter order — the #1558 contract on the DOM
          # path. A nested plan's own tree ns overrides the inherited
          # one; rows without an ns form inherit.
          class Namespaces
            attr_reader :unspellable

            def initialize(plan)
              @forms = {}
              @declared = {}
              @unspellable = false
              @qualified_attributes = false
              collect(plan[:tree])
            end

            def unspellable?
              @unspellable
            end

            # The interpretive writer's spelling heuristic: a single
            # namespace with no TYPE-qualified attributes serializes as
            # the default namespace — unprefixed element names under
            # xmlns= (OOXML DrawingML's attribute_form :unqualified,
            # and fresh WordprocessingML instances whose plain attrs
            # qualify only via attr_form); a type-namespaced attribute
            # (w:val on w:sz) forces prefixed element spellings.
            def default_spelling?
              @forms.size == 1 && !@qualified_attributes
            end

            def collect(tree)
              register(tree[:ns])
              (tree[:attributes] || []).each do |attr|
                @qualified_attributes ||= attr[:ns].is_a?(Hash)
                register(attr[:ns])
              end
              (tree[:children] || []).each do |row|
                register(row[:ns]) if row[:ns].is_a?(Hash)
                collect(row[:plan]) if row[:kind] == :nested && row[:plan]
              end
            end

            def register(ns_form)
              return if ns_form.nil? || ns_form == :none || ns_form == :any

              form = { prefix: ns_form[:prefix], uri: ns_form[:exact] }
              @forms[ns_form[:exact]] ||= form
              @unspellable = true if ns_form[:exact] && !ns_form.key?(:prefix)
            end

            # The wire spelling for a local name under this form.
            def spell(local, ns_form = nil)
              return local if default_spelling?

              form = ns_form.is_a?(Hash) ? ns_form : @forms[ns_form]
              prefix = form && form[:prefix]
              prefix ? "#{prefix}:#{local}" : local
            end

            def form_for(ns_form)
              return nil if ns_form.nil? || ns_form == :none

              ns_form.is_a?(Hash) ? ns_form : @forms[ns_form]
            end

            def declare_on(root, attr_form_prefix = nil)
              @forms.each_value do |form|
                key = form[:uri]
                next if key.nil? || @declared[key]

                @declared[key] = true
                prefix = default_spelling? ? nil : form[:prefix]
                root.add_namespace_definition(prefix, form[:uri])
                # Default-ns elements with attr_form-qualified plain
                # attributes still need the prefix declared for them.
                next if prefix || !attr_form_prefix

                root.add_namespace_definition(attr_form_prefix, form[:uri])
                @declared["#{attr_form_prefix}:#{key}"] = true
              end
            end
          end

          # Whether the compiled plan is serialize-shaped. Ordered/mixed
          # models serialize through build_ordered from element_order;
          # plain models through plan rows.
          def serializable?(plan)
            plan[:rows].all? do |_rule, _attr, kind, _sp, _del|
              SERIALIZABLE_KINDS.include?(kind)
            end
          end

          private

          def register
            Lutaml::Model::Config.default_register
          end

          def build(element, instance, plan, doc, reg = nil, ns_ctx = nil,
                    inherited_ns = nil)
            reg ||= register
            write_attributes(element, instance, plan, reg, ns_ctx)
            plan[:rows].each do |rule, attr, kind, spelling, delegate|
              value = value_of(instance, attr, delegate)
              next unless rule.render?(value, instance)

              case kind
              when :scalar
                # Multi-capture parity: an attribute that collected
                # several occurrences serializes one element per item,
                # as the interpretive writer does. A plain scalar skips
                # the Array() wrap — the common case.
                row_ns = plan[:tree][:children]&.find do |r|
                  r[:name] == rule.name.to_s
                end&.[](:ns) || inherited_ns
                if value.is_a?(::Array)
                  value.each do |item|
                    add_leaf(element,
                             ns_ctx ? ns_ctx.spell(row_name(rule, spelling), row_ns) : row_name(rule, spelling),
                             attr.serialize(item, :xml, reg), doc,
                             attrs: rule.when_attribute)
                  end
                else
                  add_leaf(element,
                           ns_ctx ? ns_ctx.spell(row_name(rule, spelling), row_ns) : row_name(rule, spelling),
                           attr.serialize(value, :xml, reg), doc,
                           attrs: rule.when_attribute)
                end
              when :collection_native, :collection_cb
                row_ns = plan[:tree][:children]&.find do |r|
                  r[:name] == rule.name.to_s
                end&.[](:ns) || inherited_ns
                Array(value).each do |item|
                  add_leaf(element,
                           ns_ctx ? ns_ctx.spell(rule.name.to_s, row_ns) : rule.name.to_s,
                           attr.serialize(item, :xml, reg), doc,
                           attrs: rule.when_attribute)
                end
              when :nested, :ordered_deferred
                Array(value).each do |item|
                  child_plan = PlanCompiler.compile(item.class, reg)
                  child_ns = child_plan[:tree][:ns] || inherited_ns
                  child = element.create_child(
                    ns_ctx ? ns_ctx.spell(child_plan[:tree][:name], child_ns) : child_plan[:tree][:name],
                  )
                  ns_ctx&.collect(child_plan[:tree])
                  if child_plan[:ordered]
                    next unless build_ordered(child, item, child_plan,
                                              doc, reg, ns_ctx, child_ns)

                  else
                    build(child, item, child_plan, doc, reg, ns_ctx, child_ns)
                  end
                end
              when :raw
                Array(value).each { |raw| element.add_child(raw.to_s) }
              when :content, :content_deferred
                Array(value).each { |run| element.add_child(doc.create_text_node(run.to_s)) }
              end
            end
          end

          # Element_order-driven emission (the interpretive order
          # applier's contract): text runs and comments verbatim, each
          # element entry consuming the next item of its collection
          # (document order). Text reads prefer the content attribute
          # when it lines up with the text-node count, so mutations to
          # the model are reflected; element_order text is the fallback.
          # PIs drop (interpretive parity). Returns nil when a nested
          # ordered child lacks element_order (caller falls back).
          def build_ordered(element, instance, plan, doc, reg = nil,
                            ns_ctx = nil, inherited_ns = nil)
            reg ||= register
            ns_ctx&.collect(plan[:tree])
            write_attributes(element, instance, plan, reg, ns_ctx)
            rows_by_name = {}
            plan[:rows].each do |rule, attr, kind, spelling, delegate|
              next unless rule.name

              rows_by_name[rule.name.to_s] ||= [rule, attr, kind, spelling,
                                                delegate]
            end
            content_entry = plan[:rows].find do |rule, _attr, kind, _sp, _del|
              CONTENT_KINDS.include?(kind) && rule.name.nil?
            end
            order = instance.element_order
            element_indices = ::Hash.new(0)
            content_attr = content_entry && content_entry[1]
            content_value = content_attr &&
              value_of(instance, content_attr, content_entry[4])
            text_node_count = order.count { |o| o.type == "Text" }
            use_content_index = content_value.is_a?(Array) &&
              content_value.length == text_node_count
            content_cdata = content_entry && content_entry[0].cdata
            text_node_index = 0

            order.each do |object|
              case object.type
              when "Text"
                text = if content_attr && !content_value.nil?
                         if use_content_index
                           content_value[text_node_index].to_s
                         elsif !content_value.is_a?(Array) && text_node_count <= 1
                           content_value.to_s
                         else
                           object.text_content || object.name
                         end
                       else
                         object.text_content || object.name
                       end
                text_node_index += 1
                next if text.nil?
                # Mixed content keeps whitespace; ordered-only skips it
                next if content_attr.nil? && text.strip.empty?

                element.add_child(content_cdata ? doc.create_cdata(text) : doc.create_text_node(text))
              when "Comment"
                element.add_child(doc.create_comment(object.text_content))
              when "Element"
                entry = rows_by_name[object.name]
                next unless entry

                _, attr, kind, _spelling, delegate = entry
                value = value_of(instance, attr, delegate)
                case kind
                when :collection_native, :collection_cb
                  index = element_indices[object.name]
                  items = Array(value)
                  next unless index < items.length

                  element_indices[object.name] += 1
                  add_leaf(element,
                           ns_ctx ? ns_ctx.spell(object.name, inherited_ns_for(plan, object.name)) : object.name,
                           attr.serialize(items[index], :xml, reg), doc)
                when :nested, :ordered_deferred
                  item = if attr.collection?
                           index = element_indices[object.name]
                           element_indices[object.name] += 1
                           Array(value)[index]
                         else
                           value
                         end
                  next unless item

                  child_plan = PlanCompiler.compile(item.class, reg)
                  child_ns = child_plan[:tree][:ns] || inherited_ns
                  child = element.create_child(
                    ns_ctx ? ns_ctx.spell(child_plan[:tree][:name], child_ns) : child_plan[:tree][:name],
                  )
                  ns_ctx&.collect(child_plan[:tree])
                  if child_plan[:ordered]
                    return nil unless build_ordered(child, item, child_plan,
                                                    doc, reg, ns_ctx, child_ns)
                  else
                    build(child, item, child_plan, doc, reg, ns_ctx, child_ns)
                  end
                when :raw
                  element.add_child(value.to_s) unless value.nil?
                when :scalar
                  add_leaf(element,
                           ns_ctx ? ns_ctx.spell(object.name, inherited_ns_for(plan, object.name)) : object.name,
                           attr.serialize(value, :xml, reg), doc)
                end
              end
            end
            true
          end

          # The effective ns form for a named row: its own exact form
          # when the rule set one, else the model's (inherited).
          def inherited_ns_for(plan, row_name)
            row = plan[:tree][:children]&.find { |r| r[:name] == row_name }
            row && row[:ns].is_a?(Hash) ? row[:ns] : plan[:tree][:ns]
          end

          # Attributes in document order when the instance recorded it
          # (parsed models), else plan row order.
          def write_attributes(element, instance, plan, reg = nil,
                               ns_ctx = nil)
            recorded = instance.attribute_order
            attr_prefixes = {}
            if ns_ctx
              (plan[:tree][:attributes] || []).each do |a|
                form = a[:ns].is_a?(Hash) ? a[:ns] : nil
                # Only rows with their own form claim a key — a nil
                # entry would shadow the attr_form default below.
                attr_prefixes[a[:name]] = form[:prefix] if form
              end
              # attribute_form :qualified: plain rows inherit the
              # model's prefix (attr_form carries it from the
              # compiler) unless the row has its own form.
              model_attr_prefix = plan[:tree][:attr_form]
              attr_prefixes.default = model_attr_prefix if model_attr_prefix
            end
            if recorded && !recorded.empty?
              by_name = {}
              plan[:attr_rows].each do |rule, attr, _sp, delegate|
                by_name[rule.name.to_s] = [rule, attr, delegate]
              end
              names = recorded |
                plan[:attr_rows].map { |rule, _a, _s, _d| rule.name.to_s }
              names.each do |name|
                write_attribute(element, instance, name, by_name[name],
                                reg, attr_prefixes[name])
              end
            else
              plan[:attr_rows].each do |rule, attr, _sp, delegate|
                write_attribute(element, instance, rule.name.to_s,
                                [rule, attr, delegate], reg,
                                attr_prefixes[rule.name.to_s])
              end
            end
          end

          def write_attribute(element, instance, name, entry, reg = nil,
                              prefix = nil)
            return unless entry

            rule, attr, delegate = entry
            value = value_of(instance, attr, delegate)
            # The interpretive writer's render gate: boolean elements
            # omit w:val when true, render_nil rules emit nil spellings
            # — the rule decides, not the value's nilness alone.
            return if value.nil? || !rule.render?(value, instance)

            spelled = prefix ? "#{prefix}:#{name}" : name
            element.set_attribute(spelled,
                                  attr.serialize(value, :xml, reg || register).to_s)
          end

          # Partition rows (#88) re-emit their discriminator: the wire
          # element carries the when_attribute pairs so the round trip
          # re-routes to the same attribute on reparse.
          def add_leaf(element, name, value, doc, attrs: nil)
            child = element.create_child(name)
            attrs&.each { |k, v| child[k.to_s] = v.to_s }
            child.add_child(doc.create_text_node(value.to_s)) unless value.nil?
            child
          end

          def value_of(instance, attr, delegate)
            if delegate
              target = instance.public_send(delegate)
              target&.public_send(attr.name)
            else
              instance.public_send(attr.name)
            end
          end

          def row_name(rule, spelling)
            (spelling || rule.name).to_s
          end
        end
      end
    end
  end
end
