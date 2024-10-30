module Lutaml
  module Model
    module Type
      class String < Value
      end

      register(:string, Lutaml::Model::Type::String)
    end
  end
end
