require_relative "key_value_mapping"

module Lutaml
  module Model
    class YamlMapping < KeyValueMapping
      def initialize
        super(:yaml)
      end
    end
  end
end
