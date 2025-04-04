require_relative "../mapping/key_value_mapping"

module Lutaml
  module Model
    module Json
      class Mapping < Lutaml::Model::KeyValueMapping
        def initialize
          super(:json)
        end

        def deep_dup
          self.class.new.tap do |new_mapping|
            new_mapping.instance_variable_set(:@mappings, duplicate_mappings)
          end
        end
      end
    end
  end
end
