require_relative "base"

module Lutaml
  module Model
    class RuleValueExtractor < Services::Base
      def initialize(rule, doc, format, attr, register, options)
        super()

        @rule = rule
        @doc = doc
        @format = format
        @attr = attr
        @register = register
        @options = options
      end

      def call
        rule_names.each do |rule_name|
          value = rule_value_for(rule_name)
          return value if Utils.initialized?(value)
        end

        uninitialized_value
      end

      private

      attr_reader :rule, :doc, :format, :attr, :register, :options

      def rule_names
        rule.multiple_mappings? ? rule.name : [rule.name]
      end

      def rule_value_for(name)
        # When name is nil but document is a hash-like object with a single key matching
        # the attribute name, extract that value. This handles the case where
        # map to: :content is used and the document is {"content": "value"}
        # Note: doc may be JSON::Ext::Generator::GeneratorMethods::Hash which is_a?(Hash) returns false
        if name.nil? && doc.respond_to?(:key?) && doc.respond_to?(:values) && doc.size == 1
          attr_name = rule.to
          if doc.key?(attr_name.to_s) || doc.key?(attr_name.to_sym)
            return doc.values.first
          end
        end

        return doc if root_or_nil?(name)
        return convert_to_format(doc, format) if rule.raw_mapping?
        return fetch_value(name) if Utils.string_or_symbol_key?(doc, name)
        return attr.default(register) if attr&.default_set?(register)

        uninitialized_value
      end

      def root_or_nil?(name)
        name.nil? || rule.root_mapping?
      end

      def fetch_value(name)
        Utils.fetch_str_or_sym(doc, name)
      end

      def convert_to_format(doc, format)
        adapter = Lutaml::Model::Config.adapter_for(format)
        adapter.new(doc).public_send(:"to_#{format}")
      end

      def uninitialized_value
        Lutaml::Model::UninitializedClass.instance
      end
    end
  end
end
