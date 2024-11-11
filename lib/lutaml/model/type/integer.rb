module Lutaml
  module Model
    module Type
      class Integer < Value
        def self.cast(value)
          return nil if value.nil?
          return 1 if value === true
          return 0 if value === false

          if value.is_a?(String) && value.match?(/^-?\d+(\.\d+)?(e-?\d+)?$/i)
            Integer(Float(value))
          else
            Integer(value)
          end
        rescue ArgumentError
          nil
        end

        # Override serialize to return Integer instead of String
        def self.serialize(value)
          return nil if value.nil?

          cast(value)
        end
      end
    end
  end
end
