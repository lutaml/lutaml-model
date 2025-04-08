module Lutaml
  module Model
    class Register
      class InvalidModelClassError < Error
        def initialize(model_name)
          super("`#{model_name}` must be a class or module")
        end
      end
    end
  end
end
