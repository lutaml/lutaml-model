# frozen_string_literal: true

module Lutaml
  module Xml
    module Leptris
      # The native emission lane of the plan fast path: instead of
      # minting the output DOM node-by-node through the Ruby
      # create_child chain, build a plan RESULT from ops
      # (leptris_plan_result_build), render it through the engine's
      # plan serializer, reparse the compact output, and write it with
      # the engine's indented document writer. Both renderings are
      # pure C; measured 2.4x faster than the DOM-mint loop on the
      # 500-row audit at a modest allocation increase.
      #
      # Byte-parity with the DOM lane holds because both lanes end at
      # the same document writer over structurally identical
      # documents: the compact emission escapes exactly as the DOM
      # text nodes do, and reparsing yields one text node per leaf,
      # matching the minted tree. The reparse is an engine-internal
      # cost, not a Ruby one.
      #
      # Emission is enabled for the provably static subset: trees with
      # no namespace form anywhere (every spelling is the unwritten
      # local name, nothing to declare, no instance-dependent
      # prefix/default flips) and the non-ordered build() shapes
      # (attributes, scalars, collections, nested models). Wildcard,
      # raw, callback, and content rows and ordered models keep the
      # DOM lane — their emission shapes are not expressible as ops
      # (or not verified to be) and the DOM lane is byte-exact.
      module NativeEmission
        ROOT_ROW = 0xFFFF_FFFF
        EMITTABLE_KINDS = %i[scalar collection nested].freeze
        # Row kinds the element_order replay can address with ops.
        # raw/child_deferred/wildcard rows keep the DOM lane.
        ORDERED_ROW_KINDS = %i[scalar collection_native collection_cb
                               nested ordered_deferred].freeze
        DEFERRED_ROW_KINDS = %i[raw ordered_deferred].freeze
        PLANNED_ROW_KINDS = %i[nested ordered_deferred].freeze
        NESTED_ROW_KINDS = %i[nested ordered_deferred].freeze
        NS_EMITTABLE_ROW_KINDS = %i[scalar collection nested
                                    collection_native
                                    ordered_deferred].freeze

        # Fiber-local buffer of reusable op Hash slots. The engine's
        # build_result copies every op into FFI memory before it
        # returns, so the Ruby hashes are dead weight past the call;
        # recycling them positionally removes one Hash allocation per
        # emitted op (four per mapped row on the emission lane) at no
        # semantic cost. Slots are cleared before every reuse, so
        # stale keys from a prior kind cannot leak into an op.
        OP_BUFFER_KEY = :lutaml_model_leptris_native_emission_op_buffer
        OP_BUFFER_BASE_KEY =
          :lutaml_model_leptris_native_emission_op_buffer_base

        class << self
          # plan: the compiled plan; instance: the emitting instance.
          # A nil instance runs the static checks only.
          def compatible?(plan, instance = nil, register = nil)
            return false if plan.nil?
            return false if namespaced_tree?(plan[:tree]) &&
              !engine_ns_prefix_safe?
            return false unless ordered_ns_emittable?(plan, instance)
            return false if plan[:ordered] && instance.is_a?(::Lutaml::Model::Serialize) &&
              instance.element_order.nil?

            subtree_gate_ok?(plan, instance, register)
          end

          # The engine's attr-row ns_prefix deep-copy fix rides
          # 1.9.407.0 (leptris#1967, fixed by leptris#1968): earlier
          # engines keep the binding's freed FFI anchor pointer in the
          # built plan and read freed heap bytes at serialize time —
          # garbage prefixes (CT_RPr:val) and empty output (the
          # lutaml-model#1126 uniword signatures) on every EXACT-ns
          # row the ops lane emits. A pure bugfix release ships no
          # capability constant, so this is a version-floor gate like
          # MIN_LEPTRIS_VERSION — the floor is the capability line.
          # Namespace-less trees never consult the descriptor's ns
          # rows and stay on the lane regardless.
          def engine_ns_prefix_safe?(version = ::Leptris::VERSION)
            Gem::Version.new(version.to_s) >=
              Gem::Version.new("1.9.407.0")
          rescue ArgumentError
            false
          end

          # Whether any tree in the emission graph carries an EXACT
          # namespace Hash (tree, attribute rows, or child rows,
          # recursively through nested plans) — the rows whose
          # ns_prefix the pre-1.9.407 engine fails to retain.
          def namespaced_tree?(tree)
            return false unless tree.is_a?(::Hash)

            return true if tree[:ns].is_a?(::Hash)
            return true if (tree[:attributes] || []).any? do |a|
              a[:ns].is_a?(::Hash)
            end

            (tree[:children] || []).any? do |r|
              next true if r[:ns].is_a?(::Hash)
              next false unless r[:plan] &&
                PLANNED_ROW_KINDS.include?(r[:kind])

              namespaced_tree?(r[:plan])
            end
          end

          # Prefixed spelling is only faithful when the ROOT instance
          # preserves a prefixed source: the DOM lane inherits the
          # root's prefix spelling down the tree (nested children
          # spell through the hoisted prefix), so one root-level fact
          # governs every EXACT row in the emission graph. Constructed
          # and default-parsed roots pin the default-xmlns form,
          # which the ops lane cannot express (uniword bold/custprops
          # format regressions when admitted).
          def prefixed_source?(instance)
            instance.is_a?(::Lutaml::Model::Serialize) &&
              !instance.xml_namespace_prefix.to_s.empty?
          end

          # The emission graph is a DAG: Descriptor.flatten_plan
          # memoizes child plans by object identity, so a shared
          # subtree keeps ONE plan slot and every parent references
          # it. The identity map mirrors that numbering exactly —
          # op plan_index values are these absolute slots.
          def emission_graph_for(plan, register)
            slot_map(emission_tree_for(plan, register))
          end

          # THE slot numbering (leptris#1966 SSOT): every consumer
          # numbering the tree — the emission graph, the flat layout,
          # the ruby gem's flatten_plan — must derive from THIS walk:
          # identity-memoized pre-order over planned rows. Shared
          # subtrees (memoized plans reachable from many parents —
          # the theme docx's clrScheme/fontScheme shapes) get ONE
          # slot at first encounter; occurrence-arithmetic (counting
          # a shared subtree's size at every reference) drifts 70/75
          # nodes on that document and handed the engine op streams
          # whose plan_index pointed at the wrong plan.
          def slot_map(tree)
            map = {}.compare_by_identity
            counter = [0]
            walk = lambda do |t|
              return map[t] if map.key?(t)

              idx = counter[0]
              counter[0] += 1
              map[t] = idx
              (t[:children] || []).each do |r|
                walk.call(r[:plan]) if r[:plan] &&
                  PLANNED_ROW_KINDS.include?(r[:kind])
              end
              idx
            end
            walk.call(tree)
            map
          end

          # A plan whose tree defers subtrees verbatim (:raw rows —
          # ordered children, e.g. uniword's document → body), at any
          # depth. The DEFERRED rows of NESTED descendants defer too:
          # an unordered root whose grandchildren defer (uniword
          # clrScheme → color → ordered srgbClr) must ride the
          # emission descriptor + identity graph — ops against the
          # parse descriptor reference child plans the compiled tree
          # never materialized (:raw rows carry no plan).
          def deferred_rows?(tree)
            (tree[:children] || []).any? do |r|
              next true if DEFERRED_ROW_KINDS.include?(r[:kind])
              next false unless r[:kind] == :nested && r[:plan]

              deferred_rows?(r[:plan])
            end
          end

          # The recursive ops-addressability gate: EVERY plan in the
          # emission graph must materialize row-for-row (an unhandled
          # kind would shift every later row_index), content runs must
          # be text-expressible (no CDATA), and every ORDERED subtree
          # instance must carry a pristine parse-built element_order
          # with Element/Text entries only (comments and PIs keep the
          # DOM lane; mutation reroutes through the reconciler).
          def subtree_gate_ok?(plan, instance, register)
            return false unless plan[:rows].all? do |row|
              gate_row_kind?(row, register)
            end
            return false if content_cdata?(plan)

            if plan[:ordered] && instance.is_a?(::Lutaml::Model::Serialize)
              return false if instance.element_order.nil?
              return false if instance.mutated_after_parse?
              return false unless instance.element_order.all? do |o|
                (o.type == "Element") ||
                  (o.type == "Text" && o.node_type != :cdata)
              end
            end

            return true unless instance.is_a?(::Lutaml::Model::Serialize)

            plan[:rows].each do |(rule, attr, kind, _sp, delegate, _type)|
              next unless rule.name
              next if kind == :child_deferred
              next unless NESTED_ROW_KINDS.include?(kind)

              value = value_of(instance, attr, delegate)
              Array(value).each do |item|
                next unless item

                # leptris#1966: the emit compiles the ITEM CLASS's
                # plan (nested_plans[[item.class, name]]) — the gate
                # must gate exactly what emit emits. Unknown classes
                # refuse here: the doc takes the DOM lane.
                child_plan = PlanCompiler.compile(item.class, register)
                return false unless child_plan
                return false unless subtree_gate_ok?(child_plan, item,
                                                     register)
              end
            end
            true
          end

          # Row kinds the emission graph can address: scalar and
          # collection rows (text ops), nested/ordered_deferred rows
          # (element ops with a compilable child), and content rows
          # (the mixed-content text channel). raw, child_deferred,
          # wildcard, and callback rows keep the DOM lane.
          def gate_row_kind?(row, register)
            kind = row[2]
            return true if PlanSerializer::CONTENT_KINDS.include?(kind)
            return true if %i[scalar collection_native
                              collection_cb child_deferred].include?(kind)
            return false unless %i[nested ordered_deferred].include?(kind)
            return false unless row[0].name

            child_type = begin
              row[5] || row[1].type(register)
            rescue StandardError
              nil
            end
            child_type.is_a?(Class) &&
              !PlanCompiler.compile(child_type, register).nil?
          end

          # Namespace-emittability for ORDERED trees: content and
          # wildcard rows carry no spelling of their own (content
          # emits text; wildcards bail in subtree_gate_ok?), so the
          # check covers the tree ns, attribute rows, and the
          # named-element rows only.
          def ordered_ns_emittable?(plan, instance_or_flag = nil)
            flag = if instance_or_flag.is_a?(::Lutaml::Model::Serialize)
                     prefixed_source?(instance_or_flag)
                   else
                     instance_or_flag
                   end
            tree = plan[:tree]
            return false unless ns_emittable?(tree[:ns], flag)
            return false if (tree[:attributes] || []).any? do |a|
              !ns_emittable?(a[:ns], flag)
            end

            (tree[:children] || []).all? do |row|
              next true unless NS_EMITTABLE_ROW_KINDS.include?(row[:kind])

              ns_emittable?(row[:ns], flag)
            end
          end

          # Only two shapes ride the ops lane: nil (:none) and
          # :unqualified — the unwritten local spelling, nothing to
          # declare — and EXACT Hash forms, ONLY under a
          # prefixed-preserved root. The engine's plan serializer
          # spells prefix:local for every EXACT row and cannot
          # express the default-xmlns form (a prefix-less EXACT row
          # emits a bare name with NO declaration, changing element
          # identity), so admitting constructed or default-parsed
          # instances flipped the pinned output format (uniword
          # bold `<b xmlns=...>` and custprops `<property>`
          # regressions). A prefixed-parsed root pins the prefixed
          # form itself — Priority 1 format preservation — and the
          # ops spelling matches it, inherited down the tree.
          def ns_emittable?(ns_form, prefixed_source = nil)
            return true if ns_form.nil? || ns_form == :unqualified
            return false unless ns_form.is_a?(Hash) && ns_form[:prefix] &&
              !ns_form[:prefix].empty?

            prefixed_source ? true : false
          end

          # len is the logical length of the buffer: slots [base, len) hold
          # the ops of the emission in progress. base is nonzero when a
          # user hook re-enters to_xml mid-emission — the inner
          # emission appends after the outer's written slots instead of
          # overwriting them. The tail is trimmed after the engine
          # consumed the result so a pathological document cannot grow
          # the buffer without bound.
          def emit(instance, plan, register)
            buf = (Thread.current[OP_BUFFER_KEY] ||= [])
            base = (Thread.current[OP_BUFFER_BASE_KEY] ||= 0)
            len = base
            result = nil
            begin
              op_slot(buf, len)
              buf[len][:kind] = :element
              buf[len][:row_index] = ROOT_ROW
              graph = if emission_lane?(plan, instance)
                        emission_graph_for(plan, register)
                      end
              root_index = graph ? graph[emission_tree_for(plan, register)] : 0
              len = if plan[:ordered] && !instance.element_order.nil?
                      emit_ordered(buf, len + 1, instance, plan, register,
                                   root_index, graph)
                    else
                      emit_element(buf, len + 1, instance, plan, register,
                                   root_index, graph)
                    end
              # A nil walk is the bail signal: a valued cycle-point or
              # type-only row the ops lane cannot spell (#1130).
              # Reset the buffer tail and hand the instance back to
              # the caller's DOM-lane fallback. The ensure's trim uses
              # the last known-good length.
              if len.nil?
                len = base
              else
                op_slot(buf, len)
                buf[len][:kind] = :end
                len += 1
                d = if emission_lane?(plan, instance)
                      emission_descriptor_for(plan, register)
                    else
                      plan[:descriptor]
                    end
                compact = d.serialize(d.build_result(buf[base, len - base]))
                result = ::Leptris::XML.parse(compact).to_xml(indent: 2,
                                                              no_decl: true)
              end
            ensure
              buf.slice!(len..) if buf.size > len
              Thread.current[OP_BUFFER_BASE_KEY] = base
            end
            result
          end

          # The emission graph is needed when the plan replays an
          # element_order (ordered roots) or materializes deferred
          # subtrees (unordered roots with :raw rows).
          def emission_lane?(plan, instance)
            return true if plan[:ordered] && !instance.element_order.nil?

            !plan[:ordered] && deferred_rows?(plan[:tree])
          end

          # Ordered/deferred plans carry :raw tree rows — the parse
          # descriptor has no child plans for them. The emission lane
          # builds its own descriptor from an emission-shaped tree:
          # dispatchable rows materialize as :nested/:scalar/
          # :collection rows with real child plans, one emission row
          # per plan row (op row_index values are plan row indices).
          def emission_tree_for(plan, register)
            build = lambda do
              tree = plan[:tree]
              ns_index = ::Lutaml::Xml::Leptris::PlanSerializer
                .ns_index_for(plan)
              {
                name: tree[:name], ns: tree[:ns], flags: tree[:flags],
                attributes: tree[:attributes],
                children: emission_rows_for(plan, ns_index, register)
              }
            end
            # Never memoize a nil-register build (child types cannot
            # materialize without a register).
            return build.call if register.nil?

            # leptris#1966: a memoized tree whose planned-children
            # count no longer matches the plan's rows is STALE — the
            # first build ran while the plan's rows were still
            # filling. Rebuild and invalidate the memos derived from
            # the tree.
            cached = plan[:emission_tree]
            if cached && (cached[:children] || []).length == plan[:rows].length
              return cached
            end

            plan[:emission_tree] = build.call
            plan[:emission_descriptor] = nil
            plan[:flat_layout_emission] = nil
            plan[:emission_tree]
          end

          def emission_descriptor_for(plan, register)
            plan[:emission_descriptor] ||= begin
              require "leptris/xml/descriptor"
              ::Leptris::XML::Descriptor.build(**emission_tree_for(plan,
                                                                  register))
            end
          end

          def emission_rows_for(plan, ns_index, register)
            rows = plan[:rows]
            content_idx = content_row_for(plan)[1]
            out = []
            rows.each_with_index do |(rule, attr, kind, _sp, _del, type), idx|
              if idx == content_idx
                # The mixed-content text channel: SCALAR text ops
                # reference this row index; the engine renders
                # CONTENT-kind rows as bare escaped text.
                out << { name: "", kind: :content }
                next
              end
              name = rule.name ? rule.name.to_s : ""
              ns = ns_index.key?(name) ? { ns: ns_index[name] } : {}
              case kind
              when :scalar
                out << { name: name, kind: :scalar, **ns }
              when :collection_native, :collection_cb
                out << { name: name, kind: :collection, **ns }
              when :nested, :ordered_deferred
                child_type = type || attr.type(register)
                child_plan = child_type &&
                  PlanCompiler.compile(child_type, register)
                out << if child_plan
                         { name: name, kind: :nested, **ns,
                           plan: emission_tree_for(child_plan, register) }
                       else
                         { name: name, kind: :scalar, **ns }
                       end
              else
                # raw/child_deferred/wildcard slots: never addressed
                # by ops (the gate rejects the plans where they
                # matter; empty child_deferred values skip emission)
                # — the placeholder keeps index alignment.
                out << { name: name, kind: :scalar, **ns }
              end
            end
            out
          end

          private

          # The (URI, local)-dispatched element_order replay — the
          # DOM lane's build_ordered contract over ops instead of
          # mints. Text entries ride SCALAR ops on the CONTENT row
          # (the engine renders CONTENT-kind rows as bare escaped
          # text); element entries dispatch like build_ordered
          # (unique-name lenient, contested (URI, local) strict with
          # URI-less fallback) and push the same element/scalar ops
          # the declaration-order walk pushes.
          def emit_ordered(buf, len, instance, plan, register, plan_index,
                           graph = nil)
            my_index = plan_index
            len = emit_attributes(buf, len, instance, plan, my_index,
                                  register)
            inherited_ns = nil
            ns_index = ::Lutaml::Xml::Leptris::PlanSerializer.ns_index_for(plan)
            rows_by_name, name_keys =
              ::Lutaml::Xml::Leptris::PlanSerializer.ordered_layout_for(
                plan, inherited_ns, ns_index, register
              )
            content_entry, content_row_index = content_row_for(plan)
            content_attr = content_entry && content_entry[1]
            content_value = content_attr &&
              value_of(instance, content_attr, content_entry[4])
            order = instance.element_order
            text_node_count = order.count { |o| o.type == "Text" }
            use_content_index = content_value.is_a?(::Array) &&
              content_value.length == text_node_count
            text_node_index = 0
            element_indices = ::Hash.new(0)
            nested_plans =
              ::Lutaml::Xml::Leptris::PlanSerializer.nested_plans_for(plan)

            order.each do |object|
              case object.type
              when "Text"
                text = if content_attr && !content_value.nil?
                         if use_content_index
                           content_value[text_node_index].to_s
                         elsif !content_value.is_a?(::Array) &&
                             text_node_count <= 1
                           content_value.to_s
                         else
                           object.text_content || object.name
                         end
                       else
                         object.text_content || object.name
                       end
                text_node_index += 1
                next if text.nil?
                next if content_attr.nil? && text.strip.empty?

                op_slot(buf, len)
                buf[len][:kind] = :scalar
                buf[len][:plan_index] = my_index
                buf[len][:row_index] = content_row_index
                buf[len][:value] = text
                len += 1
              when "Element"
                name = object.name
                keys = name_keys[name]
                if keys&.length == 1
                  dispatch_key = keys.first
                  entry = rows_by_name[dispatch_key]
                else
                  dispatch_key = [object.namespace_uri, name]
                  entry = rows_by_name[dispatch_key]
                  unless entry
                    dispatch_key = [nil, name]
                    entry = rows_by_name[dispatch_key]
                  end
                end
                next unless entry

                rule, attr, kind, _spelling, delegate, _row_ns,
                  row_index = entry
                value = value_of(instance, attr, delegate)
                case kind
                when :collection_native, :collection_cb
                  index = element_indices[dispatch_key]
                  items = Array(value)
                  next unless index < items.length

                  element_indices[dispatch_key] = index + 1
                  len = scalar_op(buf, len, my_index, row_index, attr,
                                  items[index], register)
                when :nested, :ordered_deferred
                  item = if attr.collection?
                           index = element_indices[dispatch_key]
                           element_indices[dispatch_key] = index + 1
                           Array(value)[index]
                         else
                           value
                         end
                  next unless item

                  child_plan =
                    nested_plans[[item.class, name]] ||
                    (nested_plans[[item.class, name]] =
                       PlanCompiler.compile(item.class, register))
                  child_index =
                    if graph
                      tree = emission_tree_for(child_plan, register)
                      graph[tree]
                    else
                      flat_layout_for(plan, instance, register)[row_index]&.last
                    end
                  next unless child_index

                  op_slot(buf, len)
                  buf[len][:kind] = :element
                  buf[len][:plan_index] = my_index
                  buf[len][:row_index] = row_index
                  len += 1
                  len = if child_plan[:ordered] || !item.element_order.nil?
                          emit_ordered(buf, len, item, child_plan, register,
                                       child_index, graph)
                        else
                          emit_element(buf, len, item, child_plan, register,
                                       child_index, graph)
                        end
                  return nil if len.nil?

                  op_slot(buf, len)
                  buf[len][:kind] = :end
                  len += 1
                when :child_deferred
                  # Valued cycle-point rows splice the child's own
                  # serialization verbatim under the SAME name-match
                  # guard as the unordered lane. Without this case
                  # the ordered replay silently dropped the subtree
                  # (the <b:Author/> empty-shell loss,
                  # lutaml-model#1130: Author's self-referential row
                  # is a cycle point INSIDE an ordered plan).
                  Array(value).each do |item|
                    next unless item

                    root = item.class.mappings_for(:xml, register)
                      &.root_element
                    return nil if root.nil? || root.to_s != rule.name.to_s

                    fragment = serialize_fragment(item, register)
                    return nil if fragment.nil?
                    next if fragment.empty?

                    op_slot(buf, len)
                    buf[len][:kind] = :raw
                    buf[len][:plan_index] = my_index
                    buf[len][:value] = fragment
                    len += 1
                  end
                when :scalar
                  len = scalar_op(buf, len, my_index, row_index, attr,
                                  value, register)
                end
              end
            end
            len
          end

          # [content row tuple, plan-children row index] — the mixed-
          # content text channel (rule.name nil, kind content), nil
          # when the model maps no bare content.
          def content_row_for(plan)
            return plan[:content_row_cache] if plan[:content_row_cache]

            idx = plan[:rows].index do |(rule, _attr, kind, _sp, _del, _ty)|
              PlanSerializer::CONTENT_KINDS.include?(kind) &&
                rule.name.nil?
            end
            plan[:content_row_cache] = [idx && plan[:rows][idx], idx]
          end

          def content_cdata?(plan)
            entry, = content_row_for(plan)
            entry && entry[0]&.cdata
          end

          # Cleared slot len of the buffer, reusing the Hash object a
          # previous emission left there when present. Also publishes
          # this emission's exclusive end as the fiber-local base: the
          # walk evaluates user code (model getters, default procs,
          # registered serializers) between slots, and a re-entrant
          # to_xml from that code must append after every written op,
          # never overlap this emission's slots.
          def op_slot(buf, len)
            Thread.current[OP_BUFFER_BASE_KEY] = len + 1
            (buf[len] ||= {}).clear
          end

          # plan_index: this plan's flattened index. The engine's
          # flatten_plan pushes each nested row's child plan exactly
          # once — collection members share that slot — so child flat
          # indices come from a static per-plan layout (relative to
          # this plan's index), never from a runtime counter.
          def emit_element(buf, len, instance, plan, register, plan_index,
                           graph = nil)
            my_index = plan_index
            layout = flat_layout_for(plan, instance, register)

            len = emit_attributes(buf, len, instance, plan, my_index, register)

            plan[:rows].each_with_index do |(rule, attr, kind, _spelling, delegate), row_index|
              value = value_of(instance, attr, delegate)
              next unless rule.render?(value, instance)

              case kind
              when :scalar
                # Multi-capture parity: an attribute that collected
                # several occurrences serializes one element per item,
                # as the DOM lane does.
                if value.is_a?(::Array)
                  value.each do |item|
                    len = scalar_op(buf, len, my_index, row_index, attr, item,
                                  register)
                  end
                else
                  len = scalar_op(buf, len, my_index, row_index, attr, value,
                                register)
                end
              when :collection_native, :collection_cb
                Array(value).each do |item|
                  len = scalar_op(buf, len, my_index, row_index, attr, item,
                                register)
                end
              when :child_deferred
                # leptris#1941: a VALUED cycle-point row serializes
                # the child model through its own best lane (the plan
                # serializer — native or DOM) and splices the fragment
                # verbatim through the RAW op; the empty value emits
                # nothing (the DOM lane's rule). The splice serves
                # only children whose own root element IS the row's
                # wire name — type-only models and role wrappers
                # (b:Performer wrapping an Author-typed value) need
                # the parent's row-name wrapping, which only the
                # interpretive writer performs — so anything else
                # bails the lane (the DOM ordered lane bails on
                # valued cycle points identically).
                Array(value).each do |item|
                  next unless item

                  root = item.class.mappings_for(:xml, register)
                    &.root_element
                  return nil if root.nil? || root.to_s != rule.name.to_s

                  fragment = serialize_fragment(item, register)
                  return nil if fragment.nil?
                  next if fragment.empty?

                  op_slot(buf, len)
                  buf[len][:kind] = :raw
                  buf[len][:plan_index] = my_index
                  buf[len][:value] = fragment
                  len += 1
                end
              when :content, :content_deferred
                # Mixed-content runs ride SCALAR ops on the content
                # row itself — the engine renders CONTENT-kind rows as
                # bare escaped text. Unreachable from the non-ordered
                # lane (tree_emittable? refuses content rows); the
                # ordered lane's unordered leaves land here.
                Array(value).each do |run|
                  op_slot(buf, len)
                  buf[len][:kind] = :scalar
                  buf[len][:plan_index] = my_index
                  buf[len][:row_index] = row_index
                  buf[len][:value] = run.to_s
                  len += 1
                end
              when :nested, :ordered_deferred
                child_plans = child_plans_for(plan, row_index)
                Array(value).each do |item|
                  child_plan = child_plans[item.class] ||
                    (child_plans[item.class] =
                       PlanCompiler.compile(item.class, register))
                  child_index =
                    if graph
                      tree = emission_tree_for(child_plan, register)
                      graph[tree]
                    else
                      layout[row_index]&.last
                    end
                  next unless child_index

                  op_slot(buf, len)
                  buf[len][:kind] = :element
                  buf[len][:plan_index] = my_index
                  buf[len][:row_index] = row_index
                  len += 1
                  len = if child_plan[:ordered] || !item.element_order.nil?
                          emit_ordered(buf, len, item, child_plan, register,
                                       child_index, graph)
                        else
                          emit_element(buf, len, item, child_plan,
                                       register, child_index, graph)
                        end
                  return nil if len.nil?

                  op_slot(buf, len)
                  buf[len][:kind] = :end
                  len += 1
                end
              end
            end
            len
          end

          # A child model's serialized fragment for RAW splicing: the
          # plan serializer when the child compiles (native or DOM —
          # its own best lane), else the instance's own to_xml (the
          # interpretive writer; plan-less models own that lane).
          def serialize_fragment(item, register)
            child_plan = PlanCompiler.compile(item.class, register)
            return item.to_xml if child_plan.nil?

            out = ::Lutaml::Xml::Leptris::PlanSerializer.call(item,
                                                             child_plan,
                                                             register)
            out || item.to_xml
          end

          # {nested row_index => [child tree, relative flat index]} —
          # children of this plan occupy slots my_index+1 .. in row
          # order, each nested row's subtree sized once.
          # leptris#1966 SSOT: the layout world MUST be the same
          # world the ops' descriptor comes from — emission_lane?
          # picks `d` in emit, so it picks the layout here too. The
          # old plan-only predicate let an ordered plan with a
          # built (element_order-less) instance number ops against
          # the EMISSION tree while build_result ran on the PARSE
          # descriptor (75 vs 93 slots — the theme-docx -5).
          def flat_layout_for(plan, instance = nil, register = nil)
            if instance && emission_lane?(plan, instance)
              # Never memoize a nil-register build: child types can
              # only materialize with a register (an early nil-register
              # call would cache an EMPTY layout and every later
              # emission would drop the subtrees).
              return build_flat_layout(emission_tree_for(plan, register)) if
                register.nil?

              plan[:flat_layout_emission] ||= build_flat_layout(
                emission_tree_for(plan, register),
              )
              return plan[:flat_layout_emission]
            end

            plan[:flat_layout] ||= build_flat_layout(plan[:tree])
          end

          def build_flat_layout(tree)
            
            slots = slot_map(tree)
            layout = {}
            (tree[:children] || []).each_with_index do |row, i|
              next unless row[:plan] &&
                PLANNED_ROW_KINDS.include?(row[:kind])

              layout[i] = [row[:plan], slots[row[:plan]]]
            end
            layout
            
          end

          def subtree_size(tree)
            # Mirror flatten_plan's allocation: every planned row kind
            # costs its full subtree (:nested AND :ordered_deferred —
            # counting deferred children as 1 shifted every later slot
            # after the first deferred subtree, leptris#1966).
            1 + (tree[:children] || []).sum do |row|
              if row[:plan] && PLANNED_ROW_KINDS.include?(row[:kind])
                subtree_size(row[:plan])
              else
                0
              end
            end
          end

          # The name bookkeeping is static per plan — attr_rows and the
          # tree's attribute rows never vary per instance — so the
          # name->tree row_index map is memoized on the plan. Only
          # instances carrying a recorded attribute order (parsed
          # documents whose XML attribute sequence must be replayed)
          # take the per-instance path.
          def emit_attributes(buf, len, instance, plan, plan_index, register)
            recorded = instance.attribute_order
            if recorded && !recorded.empty?
              return emit_attributes_recorded(buf, len, instance, plan,
                                              plan_index, register,
                                              recorded)
            end

            tree_attrs = plan[:tree][:attributes] || []
            row_indices = attr_row_indices_for(plan, tree_attrs)
            attr_rows = plan[:attr_rows]
            attr_rows.each do |rule, attr, _sp, delegate|
              value = value_of(instance, attr, delegate)
              next if value.nil?
              # The DOM lane's write_attribute contract: render_default:
              # false suppresses an attribute whose value is still the
              # default (a parse that omitted it), derived rules excepted.
              next unless rule.render?(value, instance)

              name = rule.name.to_s
              row_index = row_indices[name]
              next unless row_index

              op_slot(buf, len)
              buf[len][:kind] = :attr
              buf[len][:plan_index] = plan_index
              buf[len][:row_index] = row_index
              buf[len][:name] = name
              buf[len][:value] = attr.serialize(value, :xml, register).to_s
              len += 1
            end
            len
          end

          def emit_attributes_recorded(buf, len, instance, plan, plan_index,
                                       register, recorded)
            attr_rows = plan[:attr_rows]
            by_name = {}
            attr_rows.each { |rule, attr, _sp, delegate| by_name[rule.name.to_s] = [rule, attr, delegate] }
            names = recorded | attr_rows.map { |rule, _a, _s, _d| rule.name.to_s }
            tree_attrs = plan[:tree][:attributes] || []
            row_indices = attr_row_indices_for(plan, tree_attrs)
            names.each do |name|
              entry = by_name[name]
              next unless entry

              rule, attr, delegate = entry
              value = value_of(instance, attr, delegate)
              next if value.nil?
              # Same render_default contract as the plain path.
              next unless rule.render?(value, instance)

              row_index = row_indices[name]
              next unless row_index

              op_slot(buf, len)
              buf[len][:kind] = :attr
              buf[len][:plan_index] = plan_index
              buf[len][:row_index] = row_index
              buf[len][:name] = name
              buf[len][:value] = attr.serialize(value, :xml, register).to_s
              len += 1
            end
            len
          end

          # name -> tree_attrs index, first occurrence wins (same match
          # semantics as the Array#index scan it replaced).
          def attr_row_indices_for(plan, tree_attrs)
            return plan[:attr_row_indices] if plan[:attr_row_indices]

            indices = {}
            tree_attrs.each_with_index do |tree_attr, i|
              name = tree_attr[:name]
              indices[name] = i unless indices.key?(name)
            end
            plan[:attr_row_indices] = indices
          end

          def scalar_op(buf, len, plan_index, row_index, attr, value, register)
            op_slot(buf, len)
            buf[len][:kind] = :scalar
            buf[len][:plan_index] = plan_index
            buf[len][:row_index] = row_index
            buf[len][:value] = attr.serialize(value, :xml, register).to_s
            len + 1
          end

          def value_of(instance, attr, delegate)
            if delegate
              target = instance.public_send(delegate)
              target&.public_send(attr.name)
            else
              instance.public_send(attr.name)
            end
          end

          # Compiled child plans per nested row, keyed by row index and
          # then by member class. Keying through Integers and classes
          # avoids allocating a [class, name] pair per emitted child.
          def child_plans_for(plan, row_index)
            (plan[:nested_plans_by_row] ||= {})[row_index] ||= {}
          end
        end
      end
    end
  end
end
