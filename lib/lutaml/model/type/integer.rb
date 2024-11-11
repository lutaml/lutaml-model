module Lutaml
  module Model
    module Type
      class Integer < Value
        def self.cast(value)
          return nil if value.nil?
          return 1 if value === true
          return 0 if value === false

          # Exponential notation
          if value.is_a?(::String) && value.match?(/^-?\d+(\.\d+)?(e-?\d+)?$/i)
            return Integer(Float(value))
          end

          Integer(value)
        rescue ArgumentError
          # If it is not a valid integer, return nil
          nil
        end

        def self.serialize(value)
          return nil if value.nil?

          value.to_i
        end
      end

      register(:integer, Lutaml::Model::Type::Integer)
    end
  end
end
