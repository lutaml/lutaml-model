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
    # A model compiles when EVERY rule is plan-shaped; richer rows
    # defer their subtree verbatim and interpret post-walk rather
    # than opting the whole model out:
    #   - map_attribute / map_element / content / raw rows
    #   - Value-scalar types or nested Serializables
    #   - custom methods, polymorphism, unions, and ordered/mixed
    #     children capture :raw and interpret post-walk
    #   - ordered/mixed root mappings compile; the entry points
    #     reconstruct element_order from the node surface
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
          compiled = [] # [rule, attr, kind, spelling, delegate_target]
          cdata = false
          mixed_content = false
          needs_nodes = false
          collection_defaults = [] # collection attrs with element rows
          tag = 100 # type_tag echo space for callback-routed rows
          model_ns = plan_namespace(model_class, mapping, register)

          # Collection rows are NATIVE since leptris 1.9.178 —
          # collection values echo name and type_tag (the #220 gap is
          # closed), so any number routes without callbacks.
          true

          mapping.mappings(register).each do |rule|
            delegate_target = nil
            attr = if rule.delegate
                     delegate_target = model_class.attributes(register)[rule.delegate]
                     t = delegate_target&.type(register)
                     if t.is_a?(Class) && t.include?(::Lutaml::Model::Serialize)
                       t.attributes(register)[rule.to]
                     end
                   else
                     model_class.attributes(register)[rule.to]
                   end
            return nil if attr.nil?
            return nil if attr.derived?

            # Interpretive hydration materializes every mapped
            # collection, present or not; the fast path mirrors with
            # constructor-time empty arrays.
            unless rule.attribute? || !attr.collection?
              collection_defaults << attr.name.to_sym
            end

            # Fragment deferrals lose ancestor namespace context —
            # ns-qualified models keep those rules interpretive.
            fragment_needed = rule.has_custom_method_for_deserialization? ||
              rule.polymorphic_mapping? || attr.polymorphic? || attr.union?
            return nil if fragment_needed && model_ns

            if rule.attribute?
              return nil unless scalar_type?(attr, register)

              attr_rows << [rule, attr]
              plan_attrs << { name: rule.name.to_s }
            elsif rule.content_mapping?
              return nil if content_rows(rows) >= 1

              mixed_content = true
              compiled << [rule, attr,
                           attr.collection? ? :content : :content_deferred,
                           nil, delegate_target]
              rows << { name: "__content__#{compiled.size}", kind: :content }
            elsif rule.raw_mapping? || rule.raw == :element
              compiled << [rule, attr, :raw, nil, delegate_target]
              rows << { name: rule.name.to_s, kind: :raw }
            elsif rule.has_custom_method_for_deserialization?
              compiled << [rule, attr, :custom_method, nil, delegate_target]
              rows << { name: rule.name.to_s, kind: :raw }
            elsif rule.polymorphic_mapping? || attr.polymorphic? || attr.union?
              type = attr.type(register)
              return nil unless serializable_type?(type) || attr.union?

              compiled << [rule, attr, :polymorphic, nil, delegate_target]
              rows << { name: rule.name.to_s, kind: :raw }
            else
              type = attr.type(register)
              if serializable_type?(type)
                child = compile(type, register)
                return nil unless child

                if child[:ordered]
                  # Ordered/mixed children need element_order on their
                  # instances; the walk hands back plan values, not
                  # source nodes, so the subtree defers interpretively
                  # (the fragment parse runs the full machinery,
                  # order included).
                  return nil if model_ns

                  needs_nodes = true
                  compiled << [rule, attr, :ordered_deferred, nil,
                               delegate_target]
                  rows << { name: rule.name.to_s, kind: :raw }
                else
                  compiled << [rule, attr, :nested, nil, delegate_target]
                  needs_nodes ||= child[:needs_nodes]
                  nested_row = { name: rule.name.to_s, kind: :nested,
                                 plan: child[:tree] }
                  nested_row[:ns] = child_ns(rule, model_ns) if rule.namespace_set?
                  rows << nested_row
                end
              elsif rule.multiple_mappings?
                rule.name.each do |spelling|
                  compiled << [rule, attr, :spelling, spelling.to_s,
                               delegate_target]
                  rows << { name: spelling.to_s, kind: :callback,
                            type_tag: (tag += 1) }
                end
              else
                return nil unless scalar_type?(attr, register)

                row = { name: rule.name.to_s }
                row[:ns] = child_ns(rule, model_ns) if rule.namespace_set?

                if attr.collection?
                  compiled << [rule, attr, :collection_native, nil,
                               delegate_target]
                  rows << row.merge(kind: :collection)
                else
                  cdata ||= rule.cdata
                  compiled << [rule, attr, :scalar, nil, delegate_target]
                  rows << row.merge(kind: :scalar)
                end
              end
            end
          end

          flags = []
          flags << :cdata if cdata
          flags << :mixed_content if mixed_content
          flags << :ns_lenient if model_ns
          tree = { name: mapping.root_element.to_s,
                   attributes: plan_attrs, children: rows }
          tree[:ns] = model_ns if model_ns
          tree[:flags] = flags unless flags.empty?
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
            attr_rows: attr_rows, mapping: mapping,
            ordered: mapping.ordered? || mapping.mixed_content?,
            needs_nodes: needs_nodes,
            collection_defaults: collection_defaults }
        end

        def compilable_mapping?(mapping)
          mapping.root_element &&
            !(mapping.respond_to?(:root_mappings) && mapping.root_mappings)
        end

        # Attribute for a rule — delegate rules resolve against their
        # target model's attributes.
        def attr_of(model_class, rule, register)
          attr = model_class.attributes(register)[rule.to]
          return attr if attr || !rule.delegate

          target = model_class.attributes(register)[rule.delegate]
          t = target&.type(register)
          if t.is_a?(Class) && t.include?(::Lutaml::Model::Serialize)
            t.attributes(register)[rule.to]
          end
        end

        # Rule-level namespace → ChildPlan ns form (leptris 1.9.178):
        # the child binds by local name under the rule's URI with any
        # prefix. Blank-namespace rules (xmlns="") match :none.
        def child_ns(rule, _model_ns)
          uri = rule.namespace
          return { exact: uri.to_s } if uri && !uri.to_s.empty?

          :none
        end

        def content_rows(rows)
          rows.count { |r| r[:kind] == :content }
        end

        # Model-level namespace: exact URI match with lenient prefixes
        # — children bind by local name under any prefix the document
        # bound to the URI (#754 adoption semantics on the engine).
        def plan_namespace(_model_class, mapping, _register)
          ns_class = mapping.namespace_class if mapping.respond_to?(:namespace_class)
          ns_class&.uri ? { exact: ns_class.uri.to_s } : nil
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
