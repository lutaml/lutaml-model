module Lutaml
  module Model
    module Type
      class Union < Value
        # Store the union type that was used for a specific attribute
        def self.track_union_type_usage(instance, attribute_name, used_type)
          return unless instance.respond_to?(:__union_types=)

          instance.__union_types ||= {}
          instance.__union_types[attribute_name] = used_type
        end

        # Get the union type that was used for a specific attribute
        def self.get_tracked_union_type(instance, attribute_name)
          return nil unless instance.respond_to?(:__union_types)

          instance.__union_types&.dig(attribute_name)
        end
      end
    end
  end
end
