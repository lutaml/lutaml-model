# frozen_string_literal: true

module Lutaml
  module Xml
    module Leptris
      # Hydrates model instances from a Descriptor#walk PlanValue tree,
      # keyed by each value's producing row name (never position — rows
      # for missing elements are simply absent). Native rows build
      # constructor kwargs; deferred rows (custom methods, polymorphism,
      # unions) capture their subtree verbatim and interpret it
      # post-walk — the fragment parse runs the existing interpretive
      # machinery on just that island. Delegate rules hydrate
      # post-instance onto their target object. Collection rows route
      # natively when a single one exists, else through callback rows
      # (their values echo name and type_tag; native collection values
      # echo neither — leptris-ruby#220).
      module PlanHydrator
        # Row kinds whose child type/plan resolve once per plan (see
        # child_row_plans).
        CHILD_ROW_KINDS = %i[nested ordered_deferred].freeze

        class << self
          # plan: the compiled plan entry for model_class
          # value: the walk root PlanValue (element)
          # node: the parsed source element (leptris); ordered/mixed
          #   plans rebuild element_order from it and ordered children
          #   hydrate natively against their own nodes
          # declaration_plan_mode: mirrors from_xml's
          #   :import_declaration_plan option (:skip records nothing;
          #   :lazy is honored as :eager — the lazy variant pins the
          #   raw engine DOM, the retention the eager default exists
          #   to avoid)
          def call(model_class, plan, value, parent: nil, node: nil,
                   register: nil, declaration_plan_mode: :eager)
            # The child model's declared lutaml_default_register takes
            # precedence over the ambient register — the same
            # resolve_for_child contract the interpretive path applies.
            # Without it, hydration resolves the child's symbol attribute
            # types in the parent context and raises UnknownTypeError
            # for ids registered only in the child's register (#876).
            register = Lutaml::Model::Register.resolve_for_child(
              model_class, register || Lutaml::Model::Config.default_register
            )
            buckets = if node && plan[:needs_nodes]
                        element_buckets(node, plan[:contested_names])
                      end
            attr_kwargs = attributes_kwargs(plan, value, node)
            child_kwargs, children, delegates, run_children =
              children_kwargs(model_class, plan, value, buckets, register)
            plan[:collection_defaults].each do |name|
              next if attr_kwargs.key?(name) || child_kwargs.key?(name)

              child_kwargs[name] = []
            end
            # TODO.max-perf/33: the bulk constructor — allocate +
            # compiled writers, from_hash semantics — measured ~30x on
            # hydration-heavy corpora versus the generic constructor.
            attr_kwargs.update(child_kwargs)
            instance = model_class.instantiate(attr_kwargs, register)
            instance.lutaml_parent = parent if parent
            instance.lutaml_root ||= parent&.lutaml_root || parent
            # Root prefix fidelity (the interpretive transform records
            # it from the source element): prefixed sources keep their
            # prefixes through the serialize lane's format
            # preservation.
            if parent.nil? && node.respond_to?(:prefix) && node.prefix &&
                !node.prefix.empty?
              instance.xml_namespace_prefix = node.prefix
            end
            # #909: order summaries are per-instance pinned records —
            # read-only consumers skip them via the config.
            if node && plan[:ordered] &&
                Lutaml::Model::Config.instance.element_order_tracking
              instance.element_order = PlanOrder.build(node)
            end
            # Root declaration-plan parity (the interpretive
            # transform's eager mode): consumers and the interpretive
            # serialize fallback read import_declaration_plan state —
            # plan-hydrated roots must carry the same in-scope xmlns
            # declarations or round-trips drop them (#872). The root's
            # xsi:schemaLocation rides the same state (the
            # interpretive set_schema_location contract).
            if parent.nil? && node
              record_declaration_plan(instance, node, model_class) if declaration_plan_mode != :skip
              record_schema_location(instance, node)
            end
            children.each do |child|
              child.lutaml_parent = instance
              child.lutaml_root ||= instance.lutaml_root || instance
            end
            interpret_deferred(model_class, plan, value, instance, node,
                               buckets, run_children)
            route_delegates(delegates, instance)
            instance
          end

          private

          def record_declaration_plan(instance, node, model_class)
            ns_data = collect_native_namespaces(node)
            return if ns_data.empty?

            plan = Lutaml::Xml::DeclarationPlan.from_input_with_locations(
              ns_data, model_class.mappings_for(:xml)
            )
            instance.import_declaration_plan = plan if plan
          end

          # The interpretive parse stores the root's xsi:schemaLocation
          # verbatim (set_schema_location); the writer re-emits it.
          def record_schema_location(instance, node)
            schema_loc = node.attributes.each_value.find do |a|
              a.name.to_s.split(":", 2).last == "schemaLocation"
            end
            instance.raw_schema_location = schema_loc.value if schema_loc
          end

          # Same ns_data shape as ModelTransform.collect_element_namespaces,
          # collected straight off the engine nodes — no wrapper tree.
          # Iterates children with an inline element filter:
          # element_children materializes a filtered array per node,
          # which the niso allocation gate caught at scale.
          def collect_native_namespaces(element, path = [], result = {})
            own = element.namespace_definitions
            unless own.empty?
              namespaces = {}
              own.each do |ns|
                key = ns.prefix || :default
                namespaces[key] = { uri: ns.href, prefix: ns.prefix,
                                    format: ns.prefix ? :prefix : :default }
              end
              result[path.dup] = namespaces
            end
            element.children.each do |child|
              next unless child.is_a?(::Leptris::XML::Element)

              path.push(child.name)
              collect_native_namespaces(child, path, result)
              path.pop
            end
            result
          end

          def register
            Lutaml::Model::Config.default_register
          end

          def attributes_kwargs(plan, value, node = nil)
            kwargs = {}
            sole_claimants = sole_claimant_names(plan)
            ns_attr_names = plan[:ns_attr_names]
            rows = plan_attr_rows(plan)
            # #1670 batch face: one FFI crossing per node instead of
            # one per (node × attribute name). Older engine gems
            # without the snapshot fall back to the per-name reader.
            bound = rows.any? && value.respond_to?(:attributes_snapshot) &&
              value.attributes_snapshot
            rows.each do |rule, attr, name|
              v = bound ? bound[name] : value.attribute(name)
              if v.nil? && node && sole_claimants.include?(name)
                # #754/#790 parity: a sole-claimant attribute rule binds
                # any qualification (the interpretive matcher's lenient
                # recovery). The walk captures exact (URI, local) matches
                # only, so the qualified spelling is read off the node.
                v = lenient_node_attribute(node, name)
              end
              next if v.nil?

              # (URI, local) rows mirror the interpretive matcher's
              # ambiguity refusal: a second spelling of the same local
              # name binds nothing (lutaml-model#744).
              if ns_attr_names&.include?(name) &&
                  ambiguous_local_spellings?(node, name)
                next
              end

              v = v.split(rule.delimiter) if rule.delimiter
              if rule.as_list && rule.as_list[:import]
                v = rule.as_list[:import].call(v)
              end
              kwargs[attr.name.to_sym] = v
            end
            kwargs
          end

          # True when the node carries more than one spelling of the
          # local name (any qualification). Only consulted for exact-URI
          # attribute rows.
          def ambiguous_local_spellings?(node, local_name)
            return false unless node.respond_to?(:attributes)

            seen = false
            node.attributes.each_value do |attr|
              name = attr.name.to_s
              name = name.split(":").last if name.include?(":")
              next unless name == local_name

              return true if seen

              seen = true
            end
            false
          end

          # A captured-but-empty child marshals as a nil string value.
          # The interpretive pipeline classifies the raw "" through the
          # rule's value map (:empty key) — the :empty directive (the
          # plain-rule default) keeps it as "", :nil binds nil, and any
          # other directive means uninitialized, i.e. no binding.
          def mapped_empty_value(rule)
            case rule.value_map(:from)[:empty]
            when :nil then nil
            when :empty then ""
            else :skip
            end
          end

          def mapped_capture_values(values, rule)
            return values unless values.include?(nil)

            mapped = mapped_empty_value(rule)
            out = []
            values.each do |item|
              if item.nil?
                out << mapped unless mapped == :skip
              else
                out << item
              end
            end
            out
          end

          # Wire-name strings are plan-frozen; materializing them per
          # hydration allocated two or three strings per attribute row
          # per instance.
          def plan_attr_rows(plan)
            plan[:attr_row_names] ||= plan[:attr_rows].map do |rule, attr, row_name|
              [rule, attr, row_name || rule.name.to_s]
            end
          end

          # Returns [kwargs, hydrated_child_instances, delegate_values]
          # — child instances come back so the caller can decorate
          # parent/root links once the parent exists; delegate values
          # wait for the instance (their target object must exist).
          def children_kwargs(_model_class, plan, value, buckets = nil,
                              register = nil)
            register ||= Lutaml::Model::Config.default_register
            grouped, tagged, run_children = group_children(value,
                                                           plan[:row_tags])
            buckets = nil unless buckets && plan[:needs_nodes]
            kwargs = {}
            children = []
            delegates = []
            # Lazy: models without multi-spelling rows never touch it, and
            # the block-backed Hash is a fresh object per hydrated row.
            spellings = nil
            row_tags = plan[:row_tags]
            wire_names = row_wire_names(plan)
            row_memo = child_row_plans(plan, register)
            # Array#each with a top-of-loop counter: each_with_index
            # mints an enumerator per hydrated node — 14.7K allocations
            # per parse on the pnas guardrail — and next must keep its
            # continue semantics.
            rows = plan[:rows]
            idx = -1
            # rubocop:disable Metrics/BlockLength -- one row-kind
            # dispatch table; splitting it would scatter the contract
            rows.each do |row|
              idx += 1
              rule, attr, kind, spelling, delegate, _row_type = row
              tag = row_tags&.[](idx)
              name = wire_names[idx]
              case kind
              when :scalar
                # Raw passthrough: the model constructor is the single
                # cast authority — pre-casting here doubled every cast.
                # Class transforms still apply before assignment.
                if tag && (vals = tagged[tag]) && vals.size > 1
                  # Interpretive parity: several captures into a
                  # non-collection attribute arrive as the full array.
                  v = vals.map(&:string_value)
                  if v.include?(nil)
                    v = v.map { |item| item.nil? ? mapped_empty_value(rule) : item }
                    v.reject! { |item| item == :skip }
                  end
                else
                  first = if tag
                            tagged[tag]&.first
                          else
                            grouped.dig(name, 0)
                          end
                  v = first&.string_value
                  v = mapped_empty_value(rule) if v.nil? && first
                end
                unless v.nil? || v == :skip
                  v = rule.transform_value(attr, v, :from, :xml) if rule.transform.is_a?(Class)
                  assign(kwargs, delegates, delegate, rule, attr, v)
                end
              when :wildcard_any
                # interpreted post-instance (interpret_deferred)
              when :content
                runs = content_runs(value, run_children)
                if runs.empty? && !attr.collection?
                  # An empty element's content binds through the rule's
                  # value map for scalar content attributes: "" for the
                  # plain :empty directive, nil for :nil, skipped for
                  # anything else (uninitialized).
                  bound = mapped_empty_value(rule)
                  assign(kwargs, delegates, delegate, rule, attr, bound) unless bound == :skip
                else
                  assign(kwargs, delegates, delegate, rule, attr, runs)
                end
              when :ordered_deferred
                # With a source node the child hydrates natively: one
                # walk against its own node + element_order from the
                # node's children. Without one (direct PlanHydrator
                # use), the subtree fragment-parses interpretively.
                if buckets && row_memo[idx]
                  child_type, child_plan, child_register, contested = row_memo[idx]
                  selected = child_selection(buckets, name, child_plan, contested)
                  items = (selected || []).map do |n|
                    call(child_type, child_plan,
                         child_plan[:descriptor].walk(n), node: n,
                                                          register: child_register)
                  end
                  unless items.empty?
                    children.concat(items)
                    assign(kwargs, delegates, delegate, rule, attr,
                           attr.collection? ? items : items.first)
                  end
                end
              when :child_deferred
                # Uncompilable child (cycles, opted-out shapes): each
                # source node casts through the attribute — the full
                # interpretive machinery on the bridged island,
                # identical semantics to the interpretive path.
                contested_uri = if plan[:contested_names]&.include?(name)
                                  child_type_uri(attr, register)
                                end
                elements = deferred_elements(value, name, buckets,
                                             contested_uri)
                next if elements.empty?

                results = elements.map do |element|
                  attr.cast(element, :xml, register)
                end
                unless results.empty?
                  children.concat(results)
                  assign(kwargs, delegates, delegate, rule, attr,
                         attr.collection? ? results : results.first)
                end
              when :collection_cb
                values = grouped[name].to_a.map do |item|
                  item&.string_value
                end
                values = mapped_capture_values(values, rule)
                if rule.transform.is_a?(Class)
                  values = values.map { |v| rule.transform_value(attr, v, :from, :xml) }
                end
                unless values.empty?
                  assign(kwargs, delegates, delegate, rule, attr, values)
                end
              when :collection_native
                values = if tag
                           tagged[tag].to_a.map(&:string_value)
                         else
                           native_collection(value, name)
                         end
                values = mapped_capture_values(values, rule) unless values.nil?
                unless values.nil?
                  assign(kwargs, delegates, delegate, rule, attr, values)
                end
              when :spelling
                spellings ||= Hash.new { |h, k| h[k] = [] }
                spellings[[rule, attr]] << grouped[spelling.to_s].to_a
              when :nested
                child_type, child_plan, child_register, contested = row_memo[idx]
                selected = child_selection(buckets, name, child_plan, contested)
                if selected && contested
                  # Contested name: the walk's grouped values cross-echo
                  # every same-name element into every row — dispatch
                  # per source node instead (the walk is row-scoped).
                  items = selected.map do |n|
                    call(child_type, child_plan,
                         child_plan[:descriptor].walk(n), node: n,
                                                          register: child_register)
                  end
                else
                  values = grouped.fetch(name, [])
                  cursor = if child_plan[:needs_nodes] && buckets
                             selected
                           end
                  # Indexed loop: each_with_index.map mints an
                  # enumerator per node with nested rows.
                  count = values.size
                  items = Array.new(count)
                  pos = 0
                  while pos < count
                    items[pos] = call(child_type, child_plan, values[pos],
                                      node: cursor && cursor[pos],
                                      register: child_register)
                    pos += 1
                  end
                end
                next if items.empty?

                children.concat(items)
                assign(kwargs, delegates, delegate, rule, attr,
                       attr.collection? ? items : items.first)
              end
            end
            # rubocop:enable Metrics/BlockLength
            unless !spellings || spellings.empty?
              spellings.each do |(rule, attr), groups|
                # Interpretive order for shared-attribute groups is
                # spelling-group order (first spelling's matches, then
                # the next's), not interleaved document order.
                values = groups.compact.flatten.map(&:string_value)
                next if values.empty?

                delegate = delegate_of(plan, rule)
                assign(kwargs, delegates, delegate, rule, attr,
                       attr.collection? ? values : values.first)
              end
            end
            [kwargs, children, delegates, run_children]
          end

          # Deferred islands: raw subtrees become wrapper elements via a
          # fragment parse, then the interpretive machinery runs on just
          # that island — custom method invocation with an
          # element-shaped argument, or the polymorphic/union cast.
          # With the source node available the island wraps the ORIGINAL
          # node (no fragment parse — the reparse dominated deferred
          # hydration). Ordered children only land here without a node.
          def interpret_deferred(model_class, plan, value, instance, node = nil,
                                 buckets = nil, run_children = nil)
            # Array#each + top counter: no per-node enumerator (see
            # children_kwargs).
            rows = plan[:rows]
            idx = -1
            rows.each do |row|
              idx += 1
              rule = row[0]
              attr = row[1]
              kind = row[2]
              wire_name = row_wire_names(plan)[idx]
              case kind
              when :content_deferred
                runs = if run_children
                         content_runs(value, run_children)
                       else
                         content_runs(value)
                       end
                if runs.empty?
                  # The interpretive pipeline classifies the raw ""
                  # through the rule's value map: the :empty directive
                  # (the plain-rule default) binds "" — the attribute is
                  # still marked set, which is what the #856 mark is
                  # about; :nil binds nil; other directives leave the
                  # binding unset.
                  instance.value_set_for(attr.name)
                  case rule.value_map(:from)[:empty]
                  when :nil
                    instance.public_send(:"#{attr.name}=", nil)
                  when :empty
                    instance.public_send(:"#{attr.name}=", "")
                  end
                  next
                end

                # Non-collection content attrs hold the joined text
                # (the interpretive path assigns element text, the runs
                # concatenated).
                instance.public_send(:"#{attr.name}=", runs.join)
              when :raw
                raws = raw_strings(value, wire_name)
                next if raws.empty?

                instance.public_send(:"#{attr.name}=",
                                     attr.collection? ? raws : raws.first)
              when :custom_method
                elements = deferred_elements(value, wire_name, buckets)
                next if elements.empty?

                args = attr.collection? ? elements : elements.first
                rule.deserialize(instance, args,
                                 model_class.attributes(register),
                                 model_class)
              when :ordered_deferred
                next if node # hydrated natively in children_kwargs

                results = deferred_elements(value, wire_name, buckets).map do |element|
                  attr.cast(element, :xml, register,
                            lutaml_parent: instance,
                            lutaml_root: instance.lutaml_root || instance)
                end
                next if results.empty?

                instance.public_send(:"#{attr.name}=",
                                     attr.collection? ? results : results.first)
              when :wildcard_any
                # map_any_element: every child element no named row
                # claims, in document order, bridged as wrappers — the
                # interpretive pass's contract. The wildcard row's
                # type_tag marks its captures in the walk.
                next unless node

                claimed = plan[:rows].filter_map do |wr, _wa, _wk, spelling, _wd|
                  next if wr.equal?(rule) || wr.name.nil?

                  spelling ? spelling.to_s : wr.name.to_s
                end.uniq
                elements = []
                node.children.each do |child|
                  next unless child.is_a?(::Leptris::XML::Element)
                  next if claimed.include?(child.name)

                  elements << bridge_element(child)
                end
                next if elements.empty?

                # The interpretive pass casts each collected element
                # through the attribute: String keeps the wrapper,
                # Serializable types build model instances.
                results = elements.map do |element|
                  attr.cast(element, :xml, register,
                            lutaml_parent: instance,
                            lutaml_root: instance.lutaml_root || instance)
                end
                instance.public_send(
                  :"#{attr.name}=",
                  attr.collection? ? results : results.first,
                )
              when :polymorphic
                results = deferred_elements(value, wire_name, buckets).map do |element|
                  attr.cast(element, :xml, register,
                            polymorphic: rule.polymorphic,
                            lutaml_parent: instance,
                            lutaml_root: instance.lutaml_root || instance)
                end
                next if results.empty?

                instance.public_send(:"#{attr.name}=",
                                     attr.collection? ? results : results.first)
              end
            end
          end

          # Wrapper elements for deferred rows: the ORIGINAL source
          # nodes bridged through moxml's wrapper cache (wrapper
          # construction only, no parse), falling back to a fragment
          # parse of the captured subtree when no node is available.
          # Both lists are document-ordered for the row's name.
          def deferred_elements(value, name, buckets, contested_uri = nil)
            return raw_strings(value, name).map { |raw| fragment_element(raw) } unless buckets

            nodes = buckets[name]
            return [] unless nodes

            if contested_uri
              # Contested name: bind only the (URI, local) matches —
              # the type's own mapping namespace is the row identity.
              nodes = buckets[[contested_uri, name]] || []
            end
            nodes.map { |n| bridge_element(n) }
          end

          def child_type_uri(attr, register)
            type = attr.type(register)
            return nil unless type.is_a?(Class) &&
              type.include?(::Lutaml::Model::Serialize)

            type.mappings_for(:xml, register)&.namespace_uri
          end

          def contested_name?(plan, rule)
            plan[:contested_names]&.include?(rule.name.to_s) || false
          end

          def bridge_element(node)
            Lutaml::Xml::LeptrisElement.new(
              Moxml::Node.wrap(node, bridge_context),
            )
          end

          def bridge_context
            @bridge_context ||= Moxml::Context.new(:leptris)
          end

          def route_delegates(delegates, instance)
            delegates.each do |rule, delegate_attr, attr, v|
              target = instance.public_send(rule.delegate)
              unless target
                # the interpretive path instantiates absent delegate
                # targets; mirror it
                target = delegate_attr.type(register).new
                instance.public_send(:"#{rule.delegate}=", target)
              end
              target.public_send(:"#{attr.name}=", v)
            end
          end

          def delegate_of(plan, rule)
            entry = plan[:rows].find { |r, _, _k, _| r.equal?(rule) }
            entry && entry[4]
          end

          # Delegate rules hold their values for post-instance routing
          # (the target object must exist first); plain rules land in
          # kwargs directly.
          def assign(kwargs, delegates, delegate, rule, attr, value)
            if delegate
              delegates << [rule, delegate, attr, value]
            else
              kwargs[attr.name.to_sym] = value
            end
          end

          def content_runs(value, run_children = nil)
            if run_children
              # Run wrappers are :collection groups; the text rides
              # their children (the per-group at/count crossing is what
              # the snapshot pass saves).
              return run_children.flat_map do |group|
                Array.new(group.count) { |j| group.at(j).string_value }
              end
            end

            out = []
            value.count.times do |i|
              c = value.at(i)
              next unless c.name.nil? && c.kind == :collection

              out.concat(Array.new(c.count) { |j| c.at(j).string_value })
            end
            out
          end

          # Native collection rows echo their producing row's name
          # (leptris 1.9.178).
          def native_collection(value, name)
            value.count.times do |i|
              c = value.at(i)
              next unless c.kind == :collection && c.name == name

              return Array.new(c.count) { |j| c.at(j).string_value }
            end
            nil
          end

          def raw_strings(value, name)
            out = []
            value.count.times do |idx|
              child = value.at(idx)
              if child.name == name && child.kind == :raw
                out << child.string_value
              end
            end
            out
          end

          # Fragment deferral: parse the captured subtree back into a
          # wrapper element. Ancestor namespace context is absent (the
          # compiler only defers on namespace-free model chains).
          def fragment_element(raw)
            Lutaml::Xml::Adapter::LeptrisAdapter.parse(raw).root
          end

          # Attribute names claimed by exactly one attr row — the only
          # names eligible for #754/#790 lenient binding (multi-claimant
          # names stay exact; per #841 leniency is sole-claimant-only).
          def sole_claimant_names(plan)
            # Frozen with the plan: recomputing the tally per hydration
            # showed in the #876-era profile as Enumerable#find/tally churn.
            plan[:sole_claimants] ||= plan[:attr_rows]
              .map { |rule, _attr, row_name| row_name || rule.name.to_s }.tally
              .select { |_n, c| c == 1 }.keys
          end

          # Local-name attribute lookup on the source node, qualified
          # spellings included (w:val matches rule "val").
          def lenient_node_attribute(node, local_name)
            return nil unless node.respond_to?(:attributes)

            node.attributes.each_value do |attr|
              # Leptris::XML::Attr carries the raw (possibly prefixed)
              # name; strip the prefix for the local-name comparison.
              name = attr.name.to_s
              name = name.split(":").last if name.include?(":")
              return attr.value if name == local_name
            end
            nil
          end

          def group_children(value, row_tags = nil)
            # One crossing per subtree: names/tags/children come back in
            # parallel arrays from leptris_plan_value_children_snapshot.
            # The plan-path version gate (PlanCompiler.compile) already
            # guarantees leptris >= 1.9.273.0.
            names, tags, children = value.children_snapshot
            grouped = {}
            want_tags = !row_tags.nil?
            tagged = want_tags ? {} : nil
            run_children = nil
            names.each_with_index do |name, i|
              if name.nil?
                # Content runs: same snapshot pass — at()/count() per
                # child cost a crossing and a wrapper each.
                (run_children ||= []) << children[i]
                next
              end

              child = children[i]
              (grouped[name] ||= []) << child
              if want_tags && tags[i] != 0
                (tagged[tags[i]] ||= []) << child
              end
            end
            [grouped, tagged, run_children]
          end

          # Element children bucketed by local name, document order
          # preserved — the node-side mirror of group_children for
          # ordered-child hydration. Only built when the plan's subtree
          # needs source nodes; namespace-qualified models never get
          # here (the compiler keeps them interpretive).
          # Contested names need (URI, local) node buckets; every other
          # plan hydrates from the name view alone — the qualified keys
          # are one array + hash write per child and measured as an
          # allocation regression on element-heavy corpora (niso gate).
          def element_buckets(node, contested_names = nil) 
            buckets = {}
            qualified = contested_names && !contested_names.empty?
            node.children.each do |child|
              next unless child.is_a?(::Leptris::XML::Element)

              name = child.name
              (buckets[name] ||= []) << child
              if qualified
                uri = child.namespace&.href
                (buckets[[uri, name]] ||= []) << child if uri
              end
            end
            buckets
          end

          # Selected source nodes for a child row: contested names
          # dispatch by (URI, local); every other row binds the whole
          # name bucket leniently (any qualification). The pair form
          # this replaces allocated a fresh array per row per node on
          # the ordered walk (niso gate).
          def child_selection(buckets, name, child_plan, contested)
            all = buckets && buckets[name]
            return all unless buckets && all && contested

            tree_ns = child_plan[:tree][:ns]
            exact_uri = tree_ns.is_a?(Hash) ? tree_ns[:exact] : tree_ns
            exact_uri ? (buckets[[exact_uri, name]] || []) : all
          end

          # Per-(plan, register) child-row tuples, computed once and
          # reused across every node the walk hands this plan: the
          # per-node type lookup, compile hit, child register
          # resolution, and contested flag were each a measurable slice
          # of the ordered-lane allocation profile (niso gate).
          def child_row_plans(plan, register)
            plan[:child_row_memo] ||= {}
            plan[:child_row_memo][register] ||= plan[:rows].map do |rule, attr, kind, _spelling, _delegate, row_type|
              next nil unless CHILD_ROW_KINDS.include?(kind)

              child_type = row_type || attr.type(register)
              child_plan = PlanCompiler.compile(child_type, register)
              child_register = Lutaml::Model::Register.resolve_for_child(
                child_type, register
              )
              [child_type, child_plan, child_register,
               contested_name?(plan, rule)]
            end
          end

          # Plan-frozen wire names: rule.name.to_s minted a fresh string
          # per row per node in the hot loop.
          def row_wire_names(plan)
            plan[:row_wire_names] ||= plan[:rows].map do |rule, _attr, _kind, _spelling, _delegate, _row_type|
              rule.name.to_s
            end
          end
        end
      end
    end
  end
end
