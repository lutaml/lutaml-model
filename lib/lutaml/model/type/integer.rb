module Lutaml
  module Model
    module Type
      class Integer < Value
        def self.cast(value)
          return nil if value.nil?
          return 1 if value === true
          return 0 if value === false

          # Exponential notation
          if value.is_a?(::String)
            if value.match?(/^-?\d+(\.\d+)?(e-?\d+)?$/i)
              return value.to_f.to_i
            end
          end

          value.to_i
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
