# frozen_string_literal: true

module Lutaml
  module HashFormat
    module Adapter
      class Mapping < Lutaml::KeyValue::Mapping
        def initialize
          super(:hash)
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
