# frozen_string_literal: true

module Lutaml
  module Xml
    module Leptris
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
        # TODO.perf/15: env-gated histogram of why models opt out of the
        # plan path. Set PLAN_COMPILE_STATS=1 and read
        # PlanCompiler.plan_stats after a parse. Zero cost when disabled.
        def self.plan_stats
          @plan_stats ||= Hash.new(0)
        end

        def self.opt_out!(clause)
          @plan_stats ||= Hash.new(0)
          @plan_stats[clause] += 1 if ENV["PLAN_COMPILE_STATS"]
          nil
        end

        # Isolated holder: suites freeze model classes; a cache on a
        # frozen constant would be immutable (TypeProbeCache precedent).
        PLAN_CACHE = ::Class.new do
          class << self
            def cache
              @cache ||= {}
            end
          end
        end.cache

        # Name-matched element row kinds eligible for the :unqualified
        # ns form (leptris#1560). Text rows (content) match no element
        # name and wildcard rows carry their own :any.
        ROW_KINDS_NS_UNQUALIFIED = %i[scalar collection nested callback
                                      raw].freeze

        class << self
          def compile(model_class, register)
            # Version gate, not a capability probe: the plan path needs
            # leptris >= 1.9.273.0 (the child-handles snapshot). Older
            # gems take the interpretive path via the nil opt-out.
            return nil unless Leptris.plan_path_compatible?

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
            # outermost build completes and caches the real verdict. The
            # :cycle stat makes the guard visible in plan_stats — without
            # it a cyclic graph (uniword pict↔shape, sdt→sdt) reads as
            # "nil with an empty histogram", indistinguishable from a
            # silent build failure.
            stack = (Thread.current[:plan_compiler_stack] ||= [])
            return opt_out!(:cycle) if stack.include?(key)

            stack.push(key)
            begin
              PLAN_CACHE[key] = build(model_class, register)
            ensure
              stack.pop
            end
          end

          # Two engine walk defects gate walk-side consumers here; both
          # bail models to the interpretive matcher, whose exact-first-
          # then-any-qualification precedence binds what the walk drops.
          # The serialize side (PlanSerializer) reads the Ruby tree and
          # stays on the fast path. leptris 1.9.320.0 (#1587) fixes
          # both defects — the scan is skipped there and every model
          # rides the walk again.
          #
          # leptris#1585: exact-URI CHILD-row ns_uri strings are not
          # retained engine-side — once the build anchors are GC'd (a
          # warm walk plus one GC suffices), those rows stop matching
          # and hydration silently answers nil.
          #
          # leptris#1586: plain attribute rows do not leniently match
          # namespace-qualified wire attributes (uniword fontTable:
          # every w:name/w:val against a plain attr row hydrates nil).
          # A plan level carrying plain attr rows under a namespaced
          # chain therefore cannot be trusted on the walk; attribute
          # rows with an exact URI (or :any) and plans without any
          # namespace form are unaffected.
          def engine_walk_safe?(plan)
            return true if Leptris.walk_ns_safety_compatible?

            tree_safe?(plan[:tree], false)
          end

          private

          def tree_safe?(tree, ancestor_ns)
            namespaced = ancestor_ns || tree[:ns].is_a?(Hash)
            attrs = tree[:attributes] || []
            return false if namespaced &&
              attrs.any? { |a| !a[:ns].is_a?(Hash) && a[:ns] != :any }

            (tree[:children] || []).all? do |row|
              return false if row[:ns].is_a?(Hash)

              next true unless row[:kind] == :nested && row[:plan]

              tree_safe?(row[:plan], namespaced)
            end
          end

          def build(model_class, register)
            return nil unless model_class.is_a?(Class) &&
              model_class.include?(::Lutaml::Model::Serialize)

            mapping = model_class.mappings_for(:xml, register)
            return nil unless compilable_mapping?(mapping)

            rows = []
            attr_rows = [] # [[rule, attr]] hydration metadata
            plan_attrs = [] # [{name:, kind:}] rows for the engine plan
            compiled = [] # [rule, attr, kind, spelling, delegate_target]
            ns_attr_names = [] # exact-URI attribute rows (ambiguity guard)
            # Local-name claim tallies for attribute rows: a name claimed
            # by both an exact-URI row and a plain (any-namespace) row
            # cannot be dispatched by the walk — the ns form :none
            # matches any qualification, so the plain row captures the
            # qualified spelling too (#758). The interpretive matcher
            # owns shared names.
            attr_local_claims = Hash.new { |h, k| h[k] = { ns: 0, plain: 0 } }
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
              return opt_out!(:attr_nil) if attr.nil?
              return opt_out!(:derived) if attr.derived?

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
                return opt_out!(:non_plain_partition) unless plain_partition
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
              return opt_out!(:fragment_with_ns) if fragment_needed && model_ns

              if rule.attribute?
                opt = compile_attribute_row(rule, attr, register, mapping,
                                            attr_rows, plan_attrs,
                                            ns_attr_names, attr_local_claims)
                return opt_out!(opt) if opt
              elsif rule.content_mapping?
                return opt_out!(:multi_content) if content_rows(rows) >= 1

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
                return opt_out!(:non_serializable_poly) unless serializable_type?(type) || attr.union?

                needs_nodes = true
                compiled << [rule, attr, :polymorphic, nil, delegate_target]
                rows << { name: rule.name.to_s, kind: :raw }
              else
                type = attr.type(register)
                if serializable_type?(type)
                  child = compile(type, register)
                  return opt_out!(:child_uncompilable) unless child

                  if child[:ordered]
                    # Ordered/mixed children need element_order on their
                    # instances; the walk hands back plan values, not
                    # source nodes, so the subtree defers interpretively
                    # (the fragment parse runs the full machinery,
                    # order included).
                    return opt_out!(:ordered_child_with_ns) if model_ns

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
                  return opt_out!(:non_scalar) unless scalar_type?(attr, register)

                  row = { name: rule.name.to_s }
                  if rule.namespace_set?
                    row[:ns] = child_ns(rule, model_ns)
                  else
                    # The interpretive writer qualifies an element row
                    # by its attribute's type namespace when the rule
                    # declares none (resolve step 4). Rows without the
                    # type form inherit the tree namespace and land
                    # under the wrong default xmlns (uniword
                    # CoreProperties: <dc:title> spelled <title>).
                    type_ns_form = element_type_ns_form(rule, attr,
                                                        register, model_ns)
                    return opt_out!(:elem_type_ns_symbol) if type_ns_form == :bail_symbol
                    return opt_out!(:elem_type_ns_aliases) if type_ns_form == :bail_aliases

                    row[:ns] = type_ns_form if type_ns_form
                  end
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
            # Exact-URI attribute rows include their namespaced spelling
            # here: the plan serializer writes attributes by local name
            # (no prefixed wire spelling, no declaration emission —
            # leptris#1551), so these models serialize interpretively.
            namespaced = !model_ns.nil? || rows.any? { |r| r[:ns] } ||
              plan_attrs.any? { |a| a[:ns] }

            flags = []
            flags << :cdata if cdata
            flags << :mixed_content if mixed_content
            # Unconditional: a namespace-less model's children match by
            # local name even when the document declares a default or
            # prefixed namespace (#932) — the interpretive matcher's
            # unprefixed-any-URI behavior; elements (unlike attributes)
            # inherit the default xmlns, so the strict no-URI default
            # dropped every child of a namespaced document.
            flags << :ns_lenient

            # Namespace-less model child rows bind the strict unwritten
            # spelling (bare, or inherited default xmlns) on engines
            # with the leptris#1560 :unqualified form — the interpretive
            # matcher's exact no-namespace semantic, refusing prefixed
            # spellings where the ns_lenient superset bound them.
            # Rows with an explicit form (rule ns, type ns, :none, :any)
            # are untouched; name-matched element row kinds only.
            if model_ns.nil? && Leptris.ns_unqualified_rows_compatible?
              rows.each do |r|
                next if r[:ns]

                r[:ns] = :unqualified if ROW_KINDS_NS_UNQUALIFIED.include?(r[:kind])
              end
            end

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

            return opt_out!(:attr_ns_claim_conflict) if attr_local_claims
              .any? { |_, c| c[:ns].positive? && c[:plain].positive? }

            # Exact-URI attribute rows rely on the sole-claimant lenient
            # recovery for out-of-namespace spellings (the interpretive
            # exact-first-then-any-qualification precedence), and that
            # recovery reads the source node — models carrying such rows
            # must receive one through the buckets chain.
            needs_nodes = true unless ns_attr_names.empty?

            # A model combining exact-URI attribute rows with nested
            # child rows needs the walk's nested attribute capture
            # (leptris#1563, fixed 1.9.313.0): older engines drop the
            # children's attribute capture under such plans, so they
            # stay interpretive. Leaf models are unaffected.
            return opt_out!(:attr_type_ns_nested) if plan_attrs.any? { |a| a[:ns] } &&
              rows.any? && !Leptris.nested_attr_capture_compatible?

            # The catch-all row: kind :wildcard with an explicit :any ns
            # form (pad0) — the two-pass walk routes every child no
            # named row claimed here, tagged for hydrator routing.
            # Document order recovery and bridging happen in the
            # hydrator against the source node.
            if (any_rule = mapping.any_element_rule)
              any_attr = model_class.attributes(register)[any_rule.to]
              return opt_out!(:attr_nil) if any_attr.nil?

              needs_nodes = true
              wildcard_tag = tag += 1
              compiled << [any_rule, any_attr, :wildcard_any, nil, nil]
              rows << { name: "__lutaml_any__", kind: :wildcard, ns: :any,
                        type_tag: wildcard_tag }
            end

            { descriptor: descriptor, tree: tree, rows: compiled,
              attr_rows: attr_rows, mapping: mapping,
              row_tags: row_tags, namespaced: namespaced,
              ordered: mapping.ordered? || mapping.mixed_content?,
              needs_nodes: needs_nodes,
              collection_defaults: collection_defaults,
              ns_attr_names: ns_attr_names.empty? ? nil : ns_attr_names,
              wildcard_tag: (wildcard_tag if defined?(wildcard_tag)) }
          end

          # Attribute rows: identity is (URI, local) (lutaml-model#744).
          # A type-level namespace compiles into an exact-URI AttrPlan ns
          # row (libleptris 1.9.289): the walk captures the (URI, local)
          # match and the sole-claimant lenient recovery in PlanHydrator
          # keeps the interpretive exact-first-then-any-qualification
          # precedence for out-of-namespace spellings. Returns the
          # opt-out clause when the row must stay interpretive, nil
          # otherwise. Types declaring alias URI families stay
          # interpretive (a plan row holds a single exact URI and
          # non-sole-claimant alias families have no plan-side
          # resolution order); :blank / :inherit arrive as Symbols —
          # no URI to express in a row.
          def compile_attribute_row(rule, attr, register, mapping,
                                    attr_rows, plan_attrs, ns_attr_names,
                                    attr_local_claims)
            return :non_scalar unless scalar_type?(attr, register)

            attr_rows << [rule, attr]
            type_ns = attr.type_namespace_class(register)
            claim = attr_local_claims[rule.name.to_s]
            if type_ns.nil?
              # attribute_form_default :qualified on the model's
              # namespace qualifies locally-declared attributes under
              # the parent URI — the interpretive
              # resolve_attribute_namespace contract (WML: updateFields
              # w:val under xmlns="..."). The W3C default is
              # :unqualified, so == :qualified means explicitly set.
              # Rules with an explicit :blank stay unprefixed.
              ns_class = mapping.namespace_class
              if rule.namespace_param != :blank && ns_class &&
                  ns_class.attribute_form_default == :qualified
                claim[:ns] += 1
                plan_attrs << { name: rule.name.to_s,
                                ns: { exact: ns_class.uri.to_s,
                                      prefix: ns_class.prefix_default&.to_s } }
                ns_attr_names << rule.name.to_s
                return nil
              end

              claim[:plain] += 1
              plan_attrs << { name: rule.name.to_s }
              return nil
            end
            return :attr_type_ns_symbol if type_ns.is_a?(Symbol)
            return :attr_type_ns_aliases unless Leptris.attr_ns_rows_compatible? &&
              type_ns.all_uris.size == 1

            claim[:ns] += 1
            plan_attrs << { name: rule.name.to_s,
                            ns: { exact: type_ns.uri.to_s,
                                  prefix: type_ns.prefix_default&.to_s } }
            ns_attr_names << rule.name.to_s
            nil
          end

          def compilable_mapping?(mapping)
            # Mapping's uniform interface: root_mappings defaults to
            # false on the base (KeyValue overrides with its own).
            # The map_any_element catch-all rides the engine's wildcard
            # row (leptris#1552, named rows take precedence); engines
            # without the kind keep the interpretive refusal.
            return false if mapping.any_element_rule &&
              !Leptris.wildcard_rows_compatible?

            mapping.root_element && !mapping.root_mappings?
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
            return :none if uri.nil? || uri.to_s.empty?

            { exact: uri.to_s, prefix: rule.prefix&.to_s }
          end

          # Type-namespace ns form for a scalar element row, mirroring
          # the interpretive resolve_element_namespace step 4: the
          # attribute's type namespace qualifies the row when the rule
          # declares none. Rows inheriting the tree namespace (type ns
          # nil, :inherit, or equal to the model's own URI) get no form.
          # :blank and alias families have no row-expressible form —
          # the model stays interpretive.
          def element_type_ns_form(rule, attr, register, model_ns)
            return nil if rule.namespace_set?

            type_ns = attr.type_namespace_class(register)
            return nil if type_ns.nil? || type_ns == :inherit
            return :bail_symbol if type_ns.is_a?(Symbol)
            return :bail_aliases unless Leptris.attr_ns_rows_compatible? &&
              type_ns.all_uris.size == 1

            form = { exact: type_ns.uri.to_s,
                     prefix: type_ns.prefix_default&.to_s }
            return nil if form[:exact] == model_ns&.[](:exact)

            form
          end

          def content_rows(rows)
            rows.count { |r| r[:kind] == :content }
          end

          # Model-level namespace: exact URI match with lenient prefixes
          # — children bind by local name under any prefix the document
          # bound to the URI (#754 adoption semantics on the engine).
          def plan_namespace(_model_class, mapping, _register)
            # Mapping's uniform interface: namespace_class defaults
            # to nil on the base (Xml overrides).
            ns_class = mapping.namespace_class
            return nil unless ns_class&.uri

            { exact: ns_class.uri.to_s,
              prefix: ns_class.prefix_default&.to_s }
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
end
