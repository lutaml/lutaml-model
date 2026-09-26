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
          # A child model's declared lutaml_default_register takes
          # precedence over the ambient (parent) register — the same
          # contract the interpretive path applies through
          # Register.resolve_for_child. Without this, plan compilation
          # resolves the child's symbol attribute types in the parent
          # context and raises UnknownTypeError for ids registered only
          # in the child's own register (#876).
          register = Lutaml::Model::Register.resolve_for_child(
            model_class, register
          )

          key = [model_class, register]
          return PLAN_CACHE[key] if PLAN_CACHE.key?(key)

          # Cycle guard: a self-referential model (JATS sec-in-sec) must
          # resolve to nil — the interpretive pipeline owns it. The guard
          # is THREAD-LOCAL (a shared in-progress set races: a concurrent
          # same-key compile would cache false permanently — the #828
          # lesson); the nil at the cycle point is NOT cached — the
          # outermost build completes and caches the real verdict.
          stack = (Thread.current[:plan_compiler_stack] ||= [])
          return nil if stack.include?(key)

          stack.push(key)
          begin
            PLAN_CACHE[key] = build(model_class, register)
          ensure
            stack.pop
          end
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

            # Partition rows (TODO 34 step 2) ride native predicates
            # only in the plain-capture shape; any other when_attribute
            # shape stays interpretive (the suite pins nested-target
            # partitions to the interpretive path).
            unless rule.when_attribute.empty?
              t = attr.type(register)
              plain_partition = !rule.delegate &&
                !rule.has_custom_method_for_deserialization? &&
                !rule.polymorphic_mapping? &&
                !attr.polymorphic? && !attr.union? &&
                !(t.is_a?(Class) &&
                  t.include?(::Lutaml::Model::Serialize))
              return nil unless plain_partition
            end

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
              # Attribute plan rows are local-name keyed; a type-level
              # namespace makes the attribute (URI, local)-identified
              # (lutaml-model#744) — the interpretive matcher owns it
              # until plan rows carry namespace identity.
              return nil if attr.type_namespace_class(register)

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
              needs_nodes = true
              compiled << [rule, attr, :custom_method, nil, delegate_target]
              rows << { name: rule.name.to_s, kind: :raw }
            elsif rule.polymorphic_mapping? || attr.polymorphic? || attr.union?
              type = attr.type(register)
              return nil unless serializable_type?(type) || attr.union?

              needs_nodes = true
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
                # lutaml-model#88: same-name rows partitioned by the
                # rule's discriminator ride the engine's exclusive
                # predicate match (leptris 1.9.221+, #1272).
                row[:when] = rule.when_attribute unless rule.when_attribute.empty?

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

          row_tags = partition_row_tags!(compiled, rows, tag)

          # The plan serializer does not emit namespace declarations —
          # namespaced models serialize through the interpretive
          # writer (lutaml-model#847: standalone to_xml under leptris
          # dropped the element xmlns entirely).
          namespaced = !model_ns.nil? || rows.any? { |r| r[:ns] }

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
            row_tags: row_tags, namespaced: namespaced,
            ordered: mapping.ordered? || mapping.mixed_content?,
            needs_nodes: needs_nodes,
            collection_defaults: collection_defaults }
        end

        def compilable_mapping?(mapping)
          mapping.root_element &&
            !(mapping.respond_to?(:root_mappings) && mapping.root_mappings)
        end

        # Partition bookkeeping for when_attribute rows (#88, TODO
        # 34 step 2): the engine matches same-name rows exclusively —
        # first matching row wins — so predicate rows must PRECEDE any
        # plain sibling on the same name (a plain-first order
        # double-captures: the plain row takes everything and the
        # predicates still claim their matches). Every row of a
        # partitioned name gets a distinct type_tag; plan values echo
        # it back, giving the hydrator row-exact routing with no
        # per-occurrence re-derivation. Returns {compiled_index =>
        # tag} (nil when the model has no partitions). compiled and
        # rows are parallel and stay in lockstep through the reorder.
        def partition_row_tags!(compiled, rows, tag)
          by_name = rows.each_with_index
            .group_by { |(row, _)| row[:name] }
            .select { |_name, pairs| pairs.any? { |(row, _)| row[:when] } }
          return nil if by_name.empty?

          permutation = by_name.each_value.flat_map do |pairs|
            pairs.sort_by { |(row, i)| [row[:when] ? 0 : 1, i] }
              .map(&:last)
          end
          remaining = (0...rows.length).to_a - permutation
          permutation.concat(remaining)

          row_tags = {}
          permutation.each_with_index do |old_index, new_index|
            row = rows[old_index]
            next unless by_name.key?(row[:name])

            tag += 1
            row[:type_tag] = tag
            row_tags[new_index] = tag
          end
          rows.replace(permutation.map { |i| rows[i] })
          compiled.replace(permutation.map { |i| compiled[i] })
          row_tags
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
