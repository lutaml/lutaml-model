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
          def compatible?(plan)
            !plan[:ordered] && tree_emittable?(plan[:tree])
          end

          # Pre-order depth-first, children in row order — the same
          # walk Descriptor.flatten_plan performs, so the plan_index
          # counters here match the engine's flattened plans array.
          def tree_emittable?(tree)
            return false if tree[:ns]
            return false if (tree[:attributes] || []).any? { |a| a[:ns].is_a?(Hash) }

            (tree[:children] || []).all? do |row|
              EMITTABLE_KINDS.include?(row[:kind]) &&
                (row[:kind] != :nested || !row[:plan] || tree_emittable?(row[:plan]))
            end
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
              len = emit_element(buf, len + 1, instance, plan, register, 0)
              op_slot(buf, len)
              buf[len][:kind] = :end
              len += 1
              compact = plan[:descriptor].serialize(
                plan[:descriptor].build_result(buf[base, len - base]),
              )
              ::Leptris::XML.parse(compact).to_xml(indent: 2, no_decl: true)
            ensure
              buf.slice!(len..) if buf.size > len
              Thread.current[OP_BUFFER_BASE_KEY] = base
            end
          end

          private

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
          def flat_layout_for(plan)
            plan[:flat_layout] ||= begin
              layout = {}
              rel = 1
              (plan[:tree][:children] || []).each_with_index do |row, i|
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
              emit_attributes_recorded(buf, len, instance, plan, plan_index,
                                       register, recorded)
              return len
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
