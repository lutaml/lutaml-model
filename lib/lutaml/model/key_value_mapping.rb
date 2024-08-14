require_relative "key_value_mapping_rule"

module Lutaml
  module Model
    class KeyValueMapping
      attr_reader :mappings

      def initialize
        @mappings = []
      end

      def map(
        name,
        to:,
        render_nil: false,
        with: {},
        delegate: nil,
        child_mappings: nil
      )
        @mappings << KeyValueMappingRule.new(
          name,
          to: to,
          render_nil: render_nil,
          with: with,
          delegate: delegate,
          child_mappings: child_mappings,
        )
      end

      alias map_element map
    end
  end
end
