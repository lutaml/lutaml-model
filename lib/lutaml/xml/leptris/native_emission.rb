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
          # A nil instance runs the static namespace check only.
          def compatible?(plan, instance = nil)
            if plan[:ordered]
              ordered_gate_ok?(plan, instance)
            else
              tree_emittable?(plan[:tree]) &&
                (instance.nil? || instance.element_order.nil?)
            end
          end

          # Ordered models replay the parse-built element_order — the
          # interpretive anchors — so the gate needs the instance's
          # order snapshot, untouched by a writer (mutation reroutes
          # through the reconciler, a DOM-lane contract), and rows the
          # ops can address. CDATA content runs keep the DOM lane (ops
          # text escapes); comments and PIs in the order keep the DOM
          # lane (PIs drop there — the interpretive parity).
          def ordered_gate_ok?(plan, instance)
            return false unless ordered_ns_emittable?(plan)
            return false unless instance.is_a?(::Lutaml::Model::Serialize)
            return false if instance.element_order.nil?
            return false if instance.mutated_after_parse?
            return false unless plan[:rows].all? { |row|
              ORDERED_ROW_KINDS.include?(row[2])
            }
            return false if content_cdata?(plan)

            instance.element_order.all? { |o|
              (o.type == "Element") ||
                (o.type == "Text" && o.node_type != :cdata)
            }
          end

          # Namespace-emittability for ORDERED trees: content and
          # wildcard rows carry no spelling of their own (content
          # emits text; wildcards bail in ordered_gate_ok?), so the
          # check covers the tree ns, attribute rows, and the
          # named-element rows only.
          def ordered_ns_emittable?(plan)
            tree = plan[:tree]
            return false unless ns_emittable?(tree[:ns])
            return false if (tree[:attributes] || []).any? { |a|
              !ns_emittable?(a[:ns])
            }

            (tree[:children] || []).all? do |row|
              next true unless %i[scalar collection nested
                                  collection_native ordered_deferred]
                                 .include?(row[:kind])

              ns_emittable?(row[:ns])
            end
          end

          # Pre-order depth-first, children in row order — the same
          # walk Descriptor.flatten_plan performs, so the plan_index
          # counters here match the engine's flattened plans array.
          # leptris#1941: NAMESPACED trees are emittable — the plan
          # rows carry (ns_form EXACT, ns_uri, ns_prefix), the engine's
          # ops builder copies them onto the built values, and the plan
          # serializer spells prefix:local and hoists every distinct
          # (prefix, uri) declaration onto the root in first-encounter
          # order (dp_collect_decls) — the same contract the DOM lane's
          # Namespaces planner satisfies. Every ns form accepts except
          # :any (walk-leniency semantics, no wire spelling) and the
          # prefix-less EXACT Hash (no declared prefix to spell).
          def tree_emittable?(tree)
            return false unless ns_emittable?(tree[:ns])
            return false if (tree[:attributes] || []).any? { |a|
              !ns_emittable?(a[:ns])
            }

            (tree[:children] || []).all? do |row|
              EMITTABLE_KINDS.include?(row[:kind]) &&
                ns_emittable?(row[:ns]) &&
                (row[:kind] != :nested || !row[:plan] || tree_emittable?(row[:plan]))
            end
          end

          # Ordered models defer their subtree rows verbatim in the
          # parse plan (kind :raw — the ordered walk's hydration
          # contract), so the parse descriptor has no child plans for
          # nested rows and element ops cannot address them. The
          # emission lane builds its own descriptor from an
          # emission-shaped tree: dispatchable rows materialize as
          # :nested/:scalar/:collection rows with real child plans.
          # Hydration keeps the parse descriptor; only build_result +
          # serialize ride the emission graph.
          def emission_tree_for(plan, register)
            plan[:emission_tree] ||= begin
              tree = plan[:tree]
              ns_index = ::Lutaml::Xml::Leptris::PlanSerializer
                               .ns_index_for(plan)
              {
                name: tree[:name], ns: tree[:ns], flags: tree[:flags],
                attributes: tree[:attributes],
                children: emission_rows_for(plan, ns_index, register),
              }
            end
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
            content_idx = (content_row_for(plan))[1]
            out = []
            rows.each_with_index do |(rule, attr, kind, _sp, _del, type),
                                     idx|
              if idx == content_idx
                # The mixed-content text channel: SCALAR text ops
                # reference this row index; the engine renders
                # CONTENT-kind rows as bare escaped text. wire_name
                # never spells (content rows have no element form).
                out << { name: "", kind: :content }
                next
              end
              next unless rule.name
              next unless ORDERED_ROW_KINDS.include?(kind)

              name = rule.name.to_s
              row = { name: name }
              row[:ns] = ns_index[name] if ns_index.key?(name)
              case kind
              when :scalar
                row[:kind] = :scalar
              when :collection_native, :collection_cb
                row[:kind] = :collection
              when :nested, :ordered_deferred
                row[:kind] = :nested
                child_type = type || attr.type(register)
                child_plan = child_type &&
                  PlanCompiler.compile(child_type, register)
                next unless child_plan

                # Recursive materialization: the whole emission rides
                # ONE descriptor graph, so the child subtree must be
                # the child's own EMISSION tree (parse trees defer
                # their rows as :raw — unusable as op targets).
                row[:plan] = emission_tree_for(child_plan, register)
              end
              out << row
            end
            out
          end

          # nil (:none/:unqualified — unwritten) and {exact:, prefix:}
          # spell; :any and :none-symbol bail to the DOM lane.
          def ns_emittable?(ns)
            ns.nil? || ns == :unqualified ||
              (ns.is_a?(Hash) && ns[:prefix] && !ns[:prefix].empty?)
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
            begin
              op_slot(buf, len)
              buf[len][:kind] = :element
              buf[len][:row_index] = ROOT_ROW
              len = if plan[:ordered] && !instance.element_order.nil?
                      emit_ordered(buf, len + 1, instance, plan, register, 0)
                    else
                      emit_element(buf, len + 1, instance, plan, register, 0)
                    end
              op_slot(buf, len)
              buf[len][:kind] = :end
              len += 1
              d = if plan[:ordered] && !instance.element_order.nil?
                    emission_descriptor_for(plan, register)
                  else
                    plan[:descriptor]
                  end
              compact = d.serialize(d.build_result(buf[base, len - base]))
              ::Leptris::XML.parse(compact).to_xml(indent: 2, no_decl: true)
            ensure
              buf.slice!(len..) if buf.size > len
              Thread.current[OP_BUFFER_BASE_KEY] = base
            end
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
          def emit_ordered(buf, len, instance, plan, register, plan_index)
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

                _rule, attr, kind, _spelling, delegate, _row_ns,
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
                  _tree, child_rel = flat_layout_for(plan, register)[row_index]
                  next unless child_rel

                  op_slot(buf, len)
                  buf[len][:kind] = :element
                  buf[len][:plan_index] = my_index
                  buf[len][:row_index] = row_index
                  len += 1
                  len = if child_plan[:ordered] || !item.element_order.nil?
                          emit_ordered(buf, len, item, child_plan, register,
                                       my_index + child_rel)
                        else
                          emit_element(buf, len, item, child_plan, register,
                                       my_index + child_rel)
                        end
                  op_slot(buf, len)
                  buf[len][:kind] = :end
                  len += 1
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

            idx = plan[:rows].index { |(rule, _attr, kind, _sp, _del, _ty)|
              PlanSerializer::CONTENT_KINDS.include?(kind) &&
                rule.name.nil?
            }
            plan[:content_row_cache] = [idx && plan[:rows][idx], idx]
          end

          def content_cdata?(plan)
            entry, = content_row_for(plan)
            entry && entry[0] && entry[0].cdata
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
          def emit_element(buf, len, instance, plan, register, plan_index)
            my_index = plan_index
            layout = flat_layout_for(plan)

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
              when :nested
                _tree, child_rel = layout[row_index]
                next unless child_rel

                child_plans = child_plans_for(plan, row_index)
                Array(value).each do |item|
                  child_plan = child_plans[item.class] ||
                    (child_plans[item.class] =
                       PlanCompiler.compile(item.class, register))
                  op_slot(buf, len)
                  buf[len][:kind] = :element
                  buf[len][:plan_index] = my_index
                  buf[len][:row_index] = row_index
                  len += 1
                  len = emit_element(buf, len, item, child_plan,
                                   register, my_index + child_rel)
                  op_slot(buf, len)
                  buf[len][:kind] = :end
                  len += 1
                end
              end
            end
            len
          end

          # {nested row_index => [child tree, relative flat index]} —
          # children of this plan occupy slots my_index+1 .. in row
          # order, each nested row's subtree sized once.
          def flat_layout_for(plan, register = nil)
            if plan[:ordered]
              plan[:flat_layout_emission] ||= build_flat_layout(
                emission_tree_for(plan, register)
              )
              return plan[:flat_layout_emission]
            end

            plan[:flat_layout] ||= build_flat_layout(plan[:tree])
          end

          def build_flat_layout(tree)
            begin
              layout = {}
              rel = 1
              (tree[:children] || []).each_with_index do |row, i|
                next unless row[:kind] == :nested && row[:plan]

                layout[i] = [row[:plan], rel]
                rel += subtree_size(row[:plan])
              end
              layout
            end
          end

          def subtree_size(tree)
            1 + (tree[:children] || []).sum do |row|
              row[:kind] == :nested && row[:plan] ? subtree_size(row[:plan]) : 0
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

              _rule, attr, delegate = entry
              value = value_of(instance, attr, delegate)
              next if value.nil?

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
