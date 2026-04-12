# frozen_string_literal: true

module Lutaml
  module Model
    module Consolidation
      class AttributeGrouper
        # @param collection [Collection] the collection instance
        # @param map [ConsolidationMap] consolidation configuration
        # @param raw_items [Array] raw parsed instances
        def process(collection, map, raw_items)
          gather_rule = map.rules.find { |r| r.is_a?(GatherRule) }
          dispatch_block = map.rules.find { |r| r.is_a?(DispatchBlock) }

          # Group by the attribute declared in map.by
          grouped = raw_items.group_by { |item| item.public_send(map.by) }

          organized = grouped.map do |_key, items|
            build_group(map.group_class, items, gather_rule, dispatch_block)
          end

          collection.public_send(:"#{map.to}=", organized)
        end

        private

        def build_group(group_class, items, gather_rule, dispatch_block)
          instance = group_class.new

          if gather_rule && items.any?
            value = items.first.public_send(gather_rule.source)
            instance.public_send(:"#{gather_rule.target}=", value)
          end

          if dispatch_block
            Dispatcher.new(dispatch_block).dispatch(instance,
                                                    items)
          end

          instance
        end
      end
    end
  end
end
