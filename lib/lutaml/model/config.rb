# frozen_string_literal: true

module Lutaml
  module Model
    # Configuration module - single entry point for all configuration
    module Config
      extend self

      AVAILABLE_FORMATS = %i[xml json jsonl yaml toml hash].freeze
      KEY_VALUE_FORMATS = AVAILABLE_FORMATS - %i[xml]

      # Singleton Configuration instance
      def instance
        @instance ||= Configuration.new
      end

      # Adapter storage - used by FormatRegistry for dynamic format registration
      def adapters
        @adapters ||= {}
      end

      # Delegate configure to Configuration
      def configure
        yield instance
        self
      end

      # Set adapter for a format (used by FormatRegistry)
      def set_adapter_for(format, adapter)
        adapters[format] = adapter
      end

      # Get adapter for a format
      def adapter_for(format)
        adapters[format] || instance.get_adapter(format)
      end

      # Delegate adapter setters to Configuration
      AVAILABLE_FORMATS.each do |format|
        define_method(:"#{format}_adapter_type=") do |type_name|
          instance.set_adapter(format, type_name)
        end

        define_method(:"#{format}_adapter_type") do
          instance.adapter_for(format)
        end
      end

      def mappings_class_for(format)
        instance.mappings_class_for(format)
      end

      def transformer_for(format)
        instance.transformer_for(format)
      end

      def default_register
        instance.default_register
      end

      def default_register=(value)
        instance.default_register = value
      end

      def default_context_id
        instance.default_context_id
      end

      def default_context_id=(value)
        instance.default_context_id = value
      end

      # Utility method
      def to_class_name(str)
        str.to_s.split("_").map(&:capitalize).join
      end
    end
  end
end
