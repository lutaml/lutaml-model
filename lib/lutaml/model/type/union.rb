module Lutaml
  module Model
    module Type
      class Union < Value
        # Record which union type was successfully used for deserialization
        #
        # @param instance [Object] The model instance
        # @param attribute_name [Symbol] The attribute name
        # @param resolved_type [Class] The type that successfully handled the value
        # @return [void]
        def self.record_resolved_type(instance, attribute_name, resolved_type)
          return unless instance.respond_to?(:__union_types=)

          instance.__union_types ||= {}
          instance.__union_types[attribute_name] = resolved_type
        end

        # Get the union type that was used for a specific attribute
        # Retrieve the previously resolved union type for an attribute
        #
        # @param instance [Object] The model instance
        # @param attribute_name [Symbol] The attribute name
        # @return [Class, nil] The resolved type or nil if not tracked
        def self.resolved_type_for(instance, attribute_name)
          return nil unless instance.respond_to?(:__union_types)

          instance.__union_types&.dig(attribute_name)
        end
      end
    end
  end
end
