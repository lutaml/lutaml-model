require_relative "../mapping/key_value_mapping"

module Lutaml
  module Model
    module Json
      class Mapping < Lutaml::Model::KeyValueMapping
        def initialize
          super(:json)
        end
      end
    end
  end
end
