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

          def emit(instance, plan, register)
            ops = [{ kind: :element, row_index: ROOT_ROW }]
            emit_element(ops, instance, plan, register, 0)
            ops << { kind: :end }
            compact = plan[:descriptor].serialize(
              plan[:descriptor].build_result(ops),
            )
            ::Leptris::XML.parse(compact).to_xml(indent: 2, no_decl: true)
          end

          private

          # plan_index: this plan's flattened index. The engine's
          # flatten_plan pushes each nested row's child plan exactly
          # once — collection members share that slot — so child flat
          # indices come from a static per-plan layout (relative to
          # this plan's index), never from a runtime counter.
          def emit_element(ops, instance, plan, register, plan_index)
            my_index = plan_index
            layout = flat_layout_for(plan)

            emit_attributes(ops, instance, plan, my_index, register)

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
                    ops << scalar_op(my_index, row_index, attr, item, register)
                  end
                else
                  ops << scalar_op(my_index, row_index, attr, value, register)
                end
              when :collection_native, :collection_cb
                Array(value).each do |item|
                  ops << scalar_op(my_index, row_index, attr, item, register)
                end
              when :nested
                _tree, child_rel = layout[row_index]
                next unless child_rel

                Array(value).each do |item|
                  child_plan = nested_plans_for(plan)[[item.class, rule.name.to_s]] ||
                    (nested_plans_for(plan)[[item.class, rule.name.to_s]] =
                       PlanCompiler.compile(item.class, register))
                  ops << { kind: :element, plan_index: my_index,
                           row_index: row_index }
                  emit_element(ops, item, child_plan,
                               register, my_index + child_rel)
                  ops << { kind: :end }
                end
              end
            end
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

          def emit_attributes(ops, instance, plan, plan_index, register)
            recorded = instance.attribute_order
            attr_rows = plan[:attr_rows]
            if recorded && !recorded.empty?
              by_name = {}
              attr_rows.each { |rule, attr, _sp, delegate| by_name[rule.name.to_s] = [rule, attr, delegate] }
              names = recorded | attr_rows.map { |rule, _a, _s, _d| rule.name.to_s }
            else
              names = attr_rows.map { |rule, _a, _s, _d| rule.name.to_s }
              by_name = {}
              attr_rows.each { |rule, attr, _sp, delegate| by_name[rule.name.to_s] = [rule, attr, delegate] }
            end
            tree_attrs = plan[:tree][:attributes] || []
            names.each do |name|
              entry = by_name[name]
              next unless entry

              _rule, attr, delegate = entry
              value = value_of(instance, attr, delegate)
              next if value.nil?

              row_index = tree_attrs.index { |a| a[:name] == name }
              next unless row_index

              ops << { kind: :attr, plan_index: plan_index,
                       row_index: row_index, name: name,
                       value: attr.serialize(value, :xml, register).to_s }
            end
          end

          def scalar_op(plan_index, row_index, attr, value, register)
            { kind: :scalar, plan_index: plan_index, row_index: row_index,
              value: attr.serialize(value, :xml, register).to_s }
          end

          def value_of(instance, attr, delegate)
            if delegate
              target = instance.public_send(delegate)
              target&.public_send(attr.name)
            else
              instance.public_send(attr.name)
            end
          end

          def nested_plans_for(plan)
            plan[:nested_plans] ||= {}
          end
        end
      end
    end
  end
end
