module Lutaml
  module Model
    module Type
      class Union < Value
        def self.cast(value, options = {})
          value if value.nil? || Utils.uninitialized?(value)
        end
      end
    end
  end
end
