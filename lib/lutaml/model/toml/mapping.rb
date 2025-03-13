require_relative "../mapping/key_value_mapping"

module Lutaml
  module Model
    module Toml
      class Mapping < Lutaml::Model::KeyValueMapping
        def initialize
          super(:toml)
        end
      end
    end
  end
end
