module Lutaml
  module Model
    module Type
      class Decimal < Value
        def self.check_dependencies!(value)
          unless defined?(BigDecimal)
            raise TypeNotEnabledError.new("Decimal", value)
          end
        end

        def self.cast(value)
          return if value.nil?

          check_dependencies!(value)

          # If already a BigDecimal, return as-is
          return value if value.is_a?(BigDecimal)

          # Convert to string first to handle various input types
          BigDecimal(value.to_s)
        rescue ArgumentError
          nil
        end

        def self.serialize(value)
          return if value.nil?

          check_dependencies!(value)

          # Format without scientific notation and stripped of trailing zeros
          value.to_s("F")
        end
      end

      # Register the Decimal type regardless - it will raise TypeNotEnabledError
      # if used without BigDecimal
    end
  end
end
