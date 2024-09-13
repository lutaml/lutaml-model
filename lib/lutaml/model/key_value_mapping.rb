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
        to: nil,
        render_nil: false,
        with: {},
        delegate: nil,
        child_mappings: nil
      )
        validate!(name, to, with)

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

      def validate!(key, to, with)
        if to.nil? && with.empty?
          msg = ":to or :with argument is required for mapping '#{key}'"
          raise IncorrectMappingArgumentsError.new(msg)
        end

        if !with.empty? && (with[:from].nil? || with[:to].nil?)
          msg = ":with argument for mapping '#{key}' requires :to and :from keys"
          raise IncorrectMappingArgumentsError.new(msg)
        end
      end
    end
  end
end
