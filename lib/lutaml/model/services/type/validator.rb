require_relative "validator/string"
require_relative "validator/number"

module Lutaml
  module Model
    module Services
      module Type
        class Validator
          module ClassMethods
            def validate_values!(value, values)
              return if Utils.blank?(values) || values.include?(value)

              raise Lutaml::Model::Type::InvalidValueError.new(value, values)
            end

            def validate_min_max_bounds!(value, options)
              min, max = options&.values_at(:min, :max)
              return if min.nil? && max.nil?

              validate_min_bound!(value, min) if min
              validate_max_bound!(value, max) if max
            end

            def validate_min_bound!(value, min)
              return if value >= min

              raise Lutaml::Model::Type::MinBoundError.new(value, min)
            end

            def validate_max_bound!(value, max)
              return if value <= max

              raise Lutaml::Model::Type::MaxBoundError.new(value, max)
            end
          end

          extend ClassMethods
          include ClassMethods
        end
      end
    end
  end
end
