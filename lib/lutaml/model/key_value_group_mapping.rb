require_relative "key_value_mapping_rule"

module Lutaml
  module Model
    class KeyValueGroupMapping
      attr_reader :mappings

      def initialize(from, to)
        @mappings = []
        @method_from = from
        @method_to = to
        @group = "group_#{hash}"
      end

      def map(name)
        using = { from: @method_from, to: @method_to }

        @mappings << KeyValueMappingRule.new(
          name,
          methods: using,
          group: @group
        )
      end
    end
  end
end
