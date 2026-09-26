# frozen_string_literal: true

module Lutaml
  module Xml
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
          root = doc.create_element(plan[:tree][:name])
          doc.root = root
          if plan[:ordered]
            build_ordered(root, instance, plan, doc, register)
          else
            build(root, instance, plan, doc, register)
          end
          doc.to_xml(indent: 2, no_decl: true)
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

        def build(element, instance, plan, doc, reg = nil)
          reg ||= register
          write_attributes(element, instance, plan, reg)
          plan[:rows].each do |rule, attr, kind, spelling, delegate|
            value = value_of(instance, attr, delegate)
            next unless rule.render?(value, instance)

            case kind
            when :scalar
              # Multi-capture parity: an attribute that collected
              # several occurrences serializes one element per item,
              # as the interpretive writer does.
              Array(value).each do |item|
                add_leaf(element, row_name(rule, spelling),
                         attr.serialize(item, :xml, reg), doc,
                         attrs: rule.when_attribute)
              end
            when :collection_native, :collection_cb
              Array(value).each do |item|
                add_leaf(element, rule.name.to_s,
                         attr.serialize(item, :xml, reg), doc,
                         attrs: rule.when_attribute)
              end
            when :nested, :ordered_deferred
              Array(value).each do |item|
                child_plan = PlanCompiler.compile(item.class, reg)
                child = element.create_child(child_plan[:tree][:name])
                if child_plan[:ordered]
                  return nil unless build_ordered(child, item, child_plan,
                                                  doc, reg)

                else
                  build(child, item, child_plan, doc, reg)
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
        def build_ordered(element, instance, plan, doc, reg = nil)
          reg ||= register
          write_attributes(element, instance, plan, reg)
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
                add_leaf(element, object.name,
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
                child = element.create_child(child_plan[:tree][:name])
                if child_plan[:ordered]
                  return nil unless build_ordered(child, item, child_plan,
                                                  doc, reg)
                else
                  build(child, item, child_plan, doc, reg)
                end
              when :raw
                element.add_child(value.to_s) unless value.nil?
              when :scalar
                add_leaf(element, object.name,
                         attr.serialize(value, :xml, reg), doc)
              end
            end
          end
          true
        end

        # Attributes in document order when the instance recorded it
        # (parsed models), else plan row order.
        def write_attributes(element, instance, plan, _reg = nil)
          recorded = instance.attribute_order
          if recorded && !recorded.empty?
            by_name = {}
            plan[:attr_rows].each do |rule, attr, _sp, delegate|
              by_name[rule.name.to_s] = [rule, attr, delegate]
            end
            names = recorded |
              plan[:attr_rows].map { |rule, _a, _s, _d| rule.name.to_s }
            names.each do |name|
              write_attribute(element, instance, name, by_name[name])
            end
          else
            plan[:attr_rows].each do |rule, attr, _sp, delegate|
              write_attribute(element, instance, rule.name.to_s,
                              [rule, attr, delegate])
            end
          end
        end

        def write_attribute(element, instance, name, entry, reg = nil)
          return unless entry

          _rule, attr, delegate = entry
          value = value_of(instance, attr, delegate)
          return if value.nil?

          element.set_attribute(name,
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
