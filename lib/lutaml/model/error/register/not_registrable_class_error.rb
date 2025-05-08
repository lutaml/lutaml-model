module Lutaml
  module Model
    class Register
      class NotRegistrableClassError < Error
        def initialize(model_name)
          super("`#{model_name}` must be a `Lutaml::Model::Registrable` class or module")
        end
      end
    end
  end
end
