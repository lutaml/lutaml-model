# lib/lutaml/model/key_value_mapping.rb
module Lutaml
  module Model
    class KeyValueMapping
      attr_reader :mappings

      def initialize
        @mappings = []
      end

      def map(name, to:, render_nil: false, with: {})
        @mappings << MappingRule.new(name, to: to, render_nil: render_nil, with: with)
      end
    end
  end
end
