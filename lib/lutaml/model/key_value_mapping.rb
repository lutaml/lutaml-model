require_relative "key_value_mapping_rule"

module Lutaml
  module Model
    class KeyValueMapping
      def initialize
        @mappings = []
        @root_mapping = nil
      end

      def mappings
        @mappings + [@root_mapping].compact
      end

      def map(
        name,
        to: nil,
        render_nil: false,
        render_default: false,
        with: {},
        delegate: nil,
        child_mappings: nil
      )
        validate!(name, to, with)

        @mappings << KeyValueMappingRule.new(
          name,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
          child_mappings: child_mappings,
        )
      end

      alias map_element map

      def map_root(
        to: nil,
        root_mappings: {}
      )
        name = "root_mapping"
        validate!(name, to, {})

        @root_mapping = KeyValueMappingRule.new(
          name,
          to: to,
          root_mappings: root_mappings,
        )
      end

      def validate!(key, to, with)
        if to.nil? && with.empty?
          msg = ":to or :with argument is required for mapping '#{key}'"
          raise IncorrectMappingArgumentsError.new(msg)
        end

        if !with.empty? && (with[:from].nil? || with[:to].nil?)
          msg = ":with argument for mapping '#{key}' requires :to and :from keys"
          raise IncorrectMappingArgumentsError.new(msg)
        end

        validate_mappings(key)
      end

      def validate_mappings(name)
        if @root_mapping || (name == "root_mapping" && @mappings.any?)
          raise MultipleMappingsError.new("Can't define map with map_root")
        end
      end

      def deep_dup
        self.class.new.tap do |new_mapping|
          new_mapping.instance_variable_set(:@mappings, duplicate_mappings)
        end
      end

      def duplicate_mappings
        @mappings.map(&:deep_dup)
      end
    end
  end
end
