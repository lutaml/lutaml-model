require_relative "../mapping/key_value_mapping"

module Lutaml
  module Model
    module Yaml
      class Mapping < Lutaml::Model::KeyValueMapping
        def initialize
          super(:yaml)
        end
      end
    end
  end
end
