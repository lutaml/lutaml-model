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
    module PlanSerializer
      SERIALIZABLE_KINDS = %i[scalar collection_native collection_cb
                              nested raw content content_deferred].freeze

      class << self
        # plan: the compiler's entry for instance's class
        def call(instance, plan)
          doc = ::Leptris::XML::Document.create
          root = doc.create_element(plan[:tree][:name])
          doc.root = root
          build(root, instance, plan, doc)
          doc.to_xml(indent: 2, no_decl: true)
        end

        # Whether the compiled plan is serialize-shaped. Ordered/mixed
        # models keep the interpretive serializer — its order applier
        # interleaves text runs from element_order; the plan rows
        # cannot express that.
        def serializable?(plan)
          !plan[:ordered] &&
            plan[:rows].all? do |_rule, _attr, kind, _sp, _del|
              SERIALIZABLE_KINDS.include?(kind)
            end
        end

        private

        def register
          Lutaml::Model::Config.default_register
        end

        def build(element, instance, plan, doc)
          plan[:attr_rows].each do |rule, attr, _sp, delegate|
            value = value_of(instance, attr, delegate)
            next if value.nil?

            element.set_attribute(rule.name.to_s,
                             attr.serialize(value, :xml, register).to_s)
          end
          plan[:rows].each do |rule, attr, kind, spelling, delegate|
            value = value_of(instance, attr, delegate)
            next unless rule.render?(value, instance)

            case kind
            when :scalar
              add_leaf(element, row_name(rule, spelling),
                       attr.serialize(value, :xml, register), doc)
            when :collection_native, :collection_cb
              Array(value).each do |item|
                add_leaf(element, rule.name.to_s,
                         attr.serialize(item, :xml, register), doc)
              end
            when :nested
              child_plan = PlanCompiler.compile(attr.type(register), register)
              Array(value).each do |item|
                child_plan = PlanCompiler.compile(item.class, register)
                child = element.create_child(child_plan[:tree][:name])
                build(child, item, child_plan, doc)
              end
            when :raw
              Array(value).each { |raw| element.add_child(raw.to_s) }
            when :content, :content_deferred
              Array(value).each { |run| element.add_child(doc.create_text_node(run.to_s)) }
            end
          end
        end

        def add_leaf(element, name, value, doc)
          child = element.create_child(name)
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
