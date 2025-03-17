require_relative "key_value_mapping"

module Lutaml
  module Model
    class JsonMapping < KeyValueMapping
      def initialize
        super(:json)
      end
    end
  end
end
