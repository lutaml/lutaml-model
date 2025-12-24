require_relative "base"

module Lutaml
  module Model
    class RuleValueExtractor < Services::Base
      def initialize(rule, doc, format, attr, register, options, instance_object)
        super()

        @rule = rule
        @doc = doc
        @format = format
        @attr = attr
        @register = register
        @options = options
        @instance_object = instance_object
      end

      def call
        rule_names.each do |rule_name|
          value = rule_value_for(rule_name)
          return value if Utils.initialized?(value)
        end

        uninitialized_value
      end

      private

      attr_reader :rule, :doc, :format, :attr, :register, :options, :instance_object

      def rule_names
        rule.multiple_mappings? ? rule.name : [rule.name]
      end

      def rule_value_for(name)
        return doc if root_or_nil?(name)
        return convert_to_format(doc, format) if rule.raw_mapping?
        return fetch_value(name) if Utils.string_or_symbol_key?(doc, name)

        if attr
          resolver = Services::DefaultValueResolver.new(attr, register, instance_object)
          return resolver.default_value if resolver.default_set?
        end

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
