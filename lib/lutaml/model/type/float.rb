module Lutaml
  module Model
    module Type
      class Float < Value
        def self.cast(value)
          return nil if value.nil?

          value.to_f
        end

        def self.serialize(value)
          return nil if value.nil?

          value.to_f
        end
      end
    end
  end
end
