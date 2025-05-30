require_relative "base"

module Lutaml
  module Model
    class RuleValueExtractor < Services::Base
      def initialize(rule, doc, format, attr, register, options)
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
          value = transform_mapped_value(value) if should_transform_value?(value)
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
        return doc if name.nil?

        if rule.root_mapping?
          doc
        elsif rule.raw_mapping?
          convert_to_format(doc, format)
        elsif Utils.string_or_symbol_key?(doc, name)
          Utils.fetch_with_string_or_symbol_key(doc, name)
        elsif attr&.default_set?(register)
          attr.default(register)
        else
          uninitialized_value
        end
      end

      def transform_mapped_value(value)
        value.map do |k, v|
          if v.is_a?(Hash)
            transform_hash_value(v, k, options)
          else
            transform_simple_value(k, v, options)
          end
        end
      end

      def transform_hash_value(hash_value, key, options)
        hash_value.merge(
          {
            options[:key_mappings].to_instance.to_s => key,
          },
        )
      end

      def transform_simple_value(key, value, options)
        {
          options[:key_mappings].to_instance.to_s => key,
          options[:value_mappings].as_attribute.to_s => value,
        }
      end

      def should_transform_value?(value)
        (options[:key_mappings] || options[:value_mappings]) &&
          value.is_a?(Hash)
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
