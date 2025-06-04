module Lutaml
  module Model
    module Services
      module Type
        class Validator
          class << self
            def validate_values!(value, values)
              return if values.include?(value)

              raise Lutaml::Model::Type::InvalidValueError.new(value, values)
            end

            def validate_min_max_bounds!(value, min_max_bounds)
              min, max = min_max_bounds&.values_at(:min, :max)
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
        end
      end
    end
  end
end
