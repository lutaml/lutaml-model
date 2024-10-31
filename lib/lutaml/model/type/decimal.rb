module Lutaml
  module Model
    module Type
      class Decimal < Value
        def self.cast(value)
          return if value.nil?
          unless defined?(BigDecimal)
            raise TypeNotEnabledError.new("Decimal", value)
          end
          BigDecimal(value.to_s)
        end

        def self.serialize(value)
          return if value.nil?
          unless defined?(BigDecimal)
            raise TypeNotEnabledError.new("Decimal", value)
          end
          value.to_s("F")
        end
      end

      # Register the Decimal type regardless
      register(:decimal, Lutaml::Model::Type::Decimal)
    end
  end
end
