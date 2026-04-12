# frozen_string_literal: true

module Lutaml
  module Model
    module Consolidation
      class Dispatcher
        def initialize(dispatch_block)
          @dispatch_block = dispatch_block
        end

        # @param group_instance [Serializable] the GroupClass instance
        # @param items [Array] raw items to route
        def dispatch(group_instance, items)
          items.each do |item|
            value = item.public_send(@dispatch_block.discriminator)
            target_attr = @dispatch_block.route_for(value)
            next unless target_attr

            assign(group_instance, target_attr, item)
          end

          group_instance
        end

        private

        def assign(group_instance, target_attr, item)
          # Determine whether to assign whole instance or extract value
          attr_def = group_instance.class.attributes[target_attr.to_sym]
          target_type = attr_def&.type

          value = if target_type == item.class
                    item
                  elsif item.respond_to?(:value)
                    item.value
                  else
                    item
                  end

          group_instance.public_send(:"#{target_attr}=", value)
        end
      end
    end
  end
end
