module Lutaml
  module Model
    module Type
      # Base Value class for all types
      class Value
        def self.cast(value)
          return nil if value.nil?

          value.to_s
        end

        def self.serialize(value)
          return nil if value.nil?

          value.to_s
        end
      end
    end
  end
end
