module Lutaml
  module Model
    module Type
      class Decimal < Value
        def self.cast(value)
          return nil if value.nil?

          check_dependencies!(value)
          value = case value
                 when BigDecimal
                   # If already a BigDecimal, return as-is
                   value
                 else
                   # Convert to string first to handle various input types
                   BigDecimal(value.to_s)
                 end
          Model::Services::Type::Validator.validate_values!(value, values) if values_available?
          Model::Services::Type::Validator.validate_min_max_bounds!(value, min_max_bounds) if min_max_bounds_available?
          value
        rescue ArgumentError
          nil
        end

        # # xs:decimal format
        def self.serialize(value)
          return nil if value.nil?

          check_dependencies!(value)
          value = cast(value)
          value.to_s("F") # Use fixed-point notation to match test expectations
        end

        def self.check_dependencies!(value)
          unless defined?(BigDecimal)
            raise TypeNotEnabledError.new("Decimal", value)
          end
        end

        # Override to avoid serializing ruby object in YAML
        def to_yaml
          value&.to_s("F")
        end

        def self.min_max_bounds_available?
          Utils.present?(min_max_bounds)
        end

        def self.min_max_bounds
          @min_max_bounds || {}
        end

        def self.values_available?
          Utils.present?(@values)
        end

        def self.values
          @values
        end
      end
    end
  end
end
