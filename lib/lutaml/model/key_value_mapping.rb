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
        render_default: false,
        with: {},
        delegate: nil,
        child_mappings: nil,
        id: nil
      )
        validate!(name, to, with)
        uniq_id = SecureRandom.hex(8)
        if name.is_a?(Array)
          name.each do |key|
            map(key, to: to, render_nil: render_nil, render_default: render_default, with: with, delegate: delegate, child_mappings: child_mappings, id: uniq_id)
          end
          return
        end
        @mappings << KeyValueMappingRule.new(
          name,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
          child_mappings: child_mappings,
          id: id || uniq_id
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
