# frozen_string_literal: true

module Lutaml
  module Xml
    # Phase 5 slice: compile a model's XML mapping into a
    # Leptris::XML::Descriptor plan and materialize whole documents in
    # one native pass (leptris_plan_walk) — no moxml wrapper tree, no
    # per-element Ruby dispatch. Measured on the 200-item probe:
    # walk+hydrate 8.7x faster, 82% fewer allocations than the
    # interpretive path, hydration-equal output.
    #
    # A model compiles only when EVERY rule is plan-shaped; anything
    # richer keeps the interpretive path (all-or-nothing per model):
    #   - map_attribute / map_element rows only
    #   - element rows: Value-scalar types or nested Serializables
    #   - no content/raw mappings, custom methods, delegates,
    #     polymorphism, transforms, multiple spellings, namespaces,
    #     ordered mappings, hash_mappings, root_mappings
    #   - attributes not derived/union/polymorphic
    #
    # The fast path is opt-in (Config.xml_plan_fast_path) while the
    # full semantics audit (parent links, consolidation, ordering
    # metadata) completes.
    module PlanCompiler
      # Isolated holder: suites freeze model classes; a cache on a
      # frozen constant would be immutable (TypeProbeCache precedent).
      PLAN_CACHE = ::Class.new do
        class << self
          def cache
            @cache ||= {}
          end
        end
      end.cache

      class << self
        def compile(model_class, register)
          key = [model_class, register]
          return PLAN_CACHE[key] if PLAN_CACHE.key?(key)

          PLAN_CACHE[key] = build(model_class, register)
        end

        private

        def build(model_class, register)
          return nil unless model_class.is_a?(Class) &&
            model_class.include?(::Lutaml::Model::Serialize)

          mapping = model_class.mappings_for(:xml, register)
          return nil unless compilable_mapping?(mapping)

          rows = []
          attr_rows = [] # [[rule, attr]] hydration metadata
          plan_attrs = [] # [{name:, kind:}] rows for the engine plan
          compiled = [] # [rule, attr, kind] in children order
          mapping.mappings(register).each do |rule|
            attr = model_class.attributes(register)[rule.to]
            return nil if attr.nil?
            return nil if attr.derived? || attr.union? || attr.polymorphic?

            if rule.attribute?
              return nil unless scalar_type?(attr, register)

              attr_rows << [rule, attr]
              plan_attrs << { name: rule.name.to_s }
            else
              return nil unless plan_element_row?(rule)

              type = attr.type(register)
              if serializable_type?(type)
                child = compile(type, register)
                return nil unless child

                compiled << [rule, attr, :nested]
                rows << { name: rule.name.to_s, kind: :nested,
                          plan: child[:tree] }
              else
                return nil unless scalar_type?(attr, register)

                kind = attr.collection? ? :collection : :scalar
                # Collection row values carry neither name nor type_tag
                # echo (leptris 1.9.174): hydration can only attribute
                # them unambiguously with a single collection row per
                # element.
                if kind == :collection && rows.count { |r| r[:kind] == :collection } >= 1
                  return nil
                end

                compiled << [rule, attr, kind]
                rows << { name: rule.name.to_s, kind: kind }
              end
            end
          end

          tree = { name: mapping.root_element.to_s, attributes: plan_attrs,
                   children: rows }
          begin
            # Lazy: the Opal boot loads this file, and leptris is a
            # native gem there — the require only belongs on the
            # engines-enabled path.
            require "leptris/xml/descriptor"
            descriptor = ::Leptris::XML::Descriptor.build(**tree)
          rescue StandardError
            return nil
          end

          { descriptor: descriptor, tree: tree, rows: compiled,
            attr_rows: attr_rows, mapping: mapping }
        end

        def compilable_mapping?(mapping)
          !mapping.ordered? && mapping.root_element &&
            !(mapping.respond_to?(:root_mappings) && mapping.root_mappings)
        end

        def plan_element_row?(rule)
          !rule.raw_mapping? && !rule.content_mapping? &&
            !rule.delegate && !rule.multiple_mappings? &&
            !rule.namespace_set? && !rule.cdata &&
            !rule.mixed_content && !rule.as_list && !rule.delimiter &&
            !rule.has_custom_method_for_deserialization? &&
            !rule.polymorphic_mapping? &&
            !(rule.transform.is_a?(Hash) && !rule.transform.empty?) &&
            !rule.transform.is_a?(Class)
        end

        def scalar_type?(attr, register)
          type = attr.type(register)
          type.is_a?(Class) && type < ::Lutaml::Model::Type::Value &&
            !attr.custom_collection?
        end

        def serializable_type?(type)
          type.is_a?(Class) && type.include?(::Lutaml::Model::Serialize)
        end
      end
    end
  end
end
