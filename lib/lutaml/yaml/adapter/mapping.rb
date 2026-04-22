# frozen_string_literal: true

module Lutaml
  module Yaml
    module Adapter
      class Mapping < Lutaml::KeyValue::Mapping
        def initialize
          super(:yaml)
        end

        def deep_dup
          self.class.new.tap do |new_mapping|
            new_mapping.mappings = duplicate_mappings
          end
        end
      end
    end
  end
end
