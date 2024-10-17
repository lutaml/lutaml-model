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
        validate!(name, using)

        @mappings << KeyValueMappingRule.new(
          name,
          methods: using,
          group: @group
        )
      end

      def validate!(name, using)
        if !using.nil? && (using[:from].nil? || using[:to].nil?)
          msg = ":using argument for mapping '#{name}' requires :to and :from keys"
          raise IncorrectMappingArgumentsError, msg
        end
      end
    end
  end
end
