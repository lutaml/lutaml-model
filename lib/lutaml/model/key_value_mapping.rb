# lib/lutaml/model/key_value_mapping.rb
require_relative "key_value_mapping_rule"

module Lutaml
  module Model
    class KeyValueMapping
      attr_reader :mappings

      def initialize
        @mappings = []
      end

      def map(name, to:, render_nil: false, with: {}, delegate: nil)
        @mappings << KeyValueMappingRule.new(name, to: to, render_nil: render_nil, with: with, delegate: delegate)
      end

      alias map_element map
    end
  end
end
