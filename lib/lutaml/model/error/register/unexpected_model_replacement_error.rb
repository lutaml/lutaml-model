module Lutaml
  module Model
    class Register
      class UnexpectedModelReplacementError < Error
        def initialize(model, existing_model)
          super("Unexpected replacement of model #{model} with existing model #{existing_model}")
        end
      end
    end
  end
end
