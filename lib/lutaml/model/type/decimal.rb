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

      register(:decimal, Lutaml::Model::Type::Decimal) if defined?(BigDecimal)
    end
  end
end
