require_relative "key_value_mapping"

module Lutaml
  module Model
    class YamlMapping < KeyValueMapping
      def initialize
        super(:yaml)
      end

      def deep_dup
        self.class.new.tap do |new_mapping|
          new_mapping.instance_variable_set(:@mappings, duplicate_mappings)
        end
      end
    end
  end
end
