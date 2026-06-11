# frozen_string_literal: true

module Lutaml
  module Model
    # Configuration module - single entry point for all configuration.
    #
    # Delegates adapter resolution to AdapterResolver and scoped overrides
    # to AdapterScope. Keeps the configure block API for backward compatibility.
    module Config
      extend self

      # Dynamic format discovery from FormatRegistry
      def available_formats
        FormatRegistry.formats
      end

      # Dynamic key-value format discovery from FormatRegistry
      def key_value_formats
        FormatRegistry.key_value_formats
      end

      # Singleton Configuration instance
      def instance
        @instance ||= Configuration.new
      end

      # Block-scoped adapter override (thread-safe).
      #
      # Pushes adapter overrides onto a thread-local stack for the duration
      # of the block. Restores previous state on exit.
      #
      # @param overrides [Hash{Symbol => Symbol}] format => adapter type name
      # @yield block within which overrides are active
      # @return [Object] the block's return value
      #
      # @example Testing with a specific adapter
      #   Config.with_adapter(xml: :ox) do
      #     MyClass.from_xml(xml)  # Uses Ox
      #   end
      #
      # @example Library stacking
      #   Config.with_adapter(xml: :nokogiri, toml: :tomlib) do
      #     MyModel.from_xml(data)
      #   end
      def with_adapter(**overrides, &)
        AdapterScope.with(overrides, &)
      end

      # Delegate configure to Configuration
      def configure
        yield instance
        self
      end

      # Get adapter class for a format using the full resolution chain.
      #
      # @param format [Symbol] the format name
      # @return [Class, nil] the adapter class or nil
      def adapter_for(format)
        AdapterResolver.adapter_for(format)
      end

      # Store a pre-resolved adapter class for a format.
      #
      # @param format [Symbol] the format name
      # @param adapter [Class] the adapter class
      def set_adapter_for(format, adapter)
        AdapterResolver.set_adapter_class(format, adapter)
      end

      # Dynamic adapter type accessors for boot-time formats.
      # Additional formats (xml, etc.) get their accessors registered
      # via FormatRegistry.register which calls define_adapter_type_methods.
      AVAILABLE_FORMATS = %i[json jsonl yaml toml hash yamls].freeze
      KEY_VALUE_FORMATS = AVAILABLE_FORMATS

      AVAILABLE_FORMATS.each do |format|
        define_method(:"#{format}_adapter") do
          AdapterResolver.adapter_for(format)
        end

        define_method(:"#{format}_adapter=") do |adapter_klass|
          AdapterResolver.set_adapter_class(format, adapter_klass)
        end

        define_method(:"#{format}_adapter_type=") do |type_name|
          AdapterResolver.set_adapter_type(format, type_name)
        end

        define_method(:"#{format}_adapter_type") do
          AdapterResolver.configured_type(format)
        end
      end

      # Store used by classes that declare `cache_conversions`.
      # Duck-typed: anything responding to #get(key) and #set(key, value).
      # Defaults to a memory-backed Lutaml::Store::BasicStore when the
      # lutaml-store gem is loaded; assign false to disable caching, or
      # nil to return to auto-detection.
      def conversion_cache
        instance.conversion_cache
      end

      def conversion_cache=(store)
        instance.conversion_cache = store
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

      # Define dynamic adapter type accessor methods for a format.
      # Called by FormatRegistry.register when a new format is registered.
      #
      # Defines two pairs of methods:
      #   - #{format}_adapter / #{format}_adapter= — adapter class getter/setter
      #   - #{format}_adapter_type / #{format}_adapter_type= — type name getter/setter
      #
      # @param format [Symbol] the format name
      def define_adapter_type_methods(format)
        return if method_defined?(:"#{format}_adapter_type=")

        # Adapter class getter (returns Class)
        define_method(:"#{format}_adapter") do
          AdapterResolver.adapter_for(format)
        end

        # Adapter class setter (accepts Class)
        define_method(:"#{format}_adapter=") do |adapter_klass|
          AdapterResolver.set_adapter_class(format, adapter_klass)
        end

        # Adapter type name setter (accepts Symbol like :nokogiri)
        define_method(:"#{format}_adapter_type=") do |type_name|
          AdapterResolver.set_adapter_type(format, type_name)
        end

        # Adapter type name getter (returns Symbol or nil)
        define_method(:"#{format}_adapter_type") do
          AdapterResolver.configured_type(format)
        end
      end

      def to_class_name(str)
        str.to_s.split("_").map(&:capitalize).join
      end
    end
  end
end
