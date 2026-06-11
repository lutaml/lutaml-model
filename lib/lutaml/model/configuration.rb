# frozen_string_literal: true

module Lutaml
  module Model
    # Single source of truth for Lutaml::Model configuration.
    #
    # Adapter methods delegate to AdapterResolver. This class retains
    # the configure block API, register, and non-adapter settings.
    #
    # @example Basic configuration
    #   Lutaml::Model::Configuration.configure do |config|
    #     config.xml_adapter = :nokogiri
    #     config.json_adapter = :standard
    #   end
    #
    class Configuration
      attr_reader :default_register
      attr_writer :conversion_cache

      def initialize
        @default_register = :default
        @conversion_cache = nil
        @configured = false
      end

      def configure
        yield self if block_given?
        @configured = true
        self
      end

      # Store consulted by classes that declare `cache_conversions`.
      # Defaults to a memory-backed Lutaml::Store::BasicStore when the
      # lutaml-store gem is loaded (the application opts in by adding it
      # to its Gemfile and requiring "lutaml/store"). Assign any object
      # responding to #get/#set to override, false to disable caching
      # entirely, or nil to return to auto-detection.
      def conversion_cache
        return if @conversion_cache == false

        @conversion_cache ||= default_conversion_cache
      end

      def configured?
        @configured
      end

      # Dynamic accessor for adapter types — delegates to AdapterResolver
      def adapter_for(format)
        AdapterResolver.configured_type(format)
      end

      # Dynamic setter for adapter types — delegates to AdapterResolver
      def set_adapter(format, adapter_type)
        AdapterResolver.set_adapter_type(format, adapter_type)
      end

      # Get adapter class for a format
      def get_adapter(format)
        AdapterResolver.adapter_for(format)
      end

      def default_register=(value)
        @default_register = case value
                            when Symbol then value
                            when Lutaml::Model::Register then value.id
                            else
                              raise ArgumentError,
                                    "Unknown register: #{value.inspect}. " \
                                    "Expected a Symbol or a Lutaml::Model::Register instance."
                            end
      end

      alias default_context_id default_register
      alias default_context_id= default_register=

      # Reset configuration to defaults
      def reset!
        @default_register = :default
        @conversion_cache = nil
        @configured = false
        AdapterResolver.reset!
        AdapterScope.reset!
      end

      def to_h
        {
          default_register: @default_register,
          configured: @configured,
        }
      end

      def mappings_class_for(format)
        Lutaml::Model::FormatRegistry.mappings_class_for(format)
      end

      def transformer_for(format)
        Lutaml::Model::FormatRegistry.transformer_for(format)
      end

      # Adapter accessors are defined dynamically by FormatRegistry.register
      # via define_method. These forward to AdapterResolver.
      # The generic set_adapter/get_adapter handle any format.

      private

      def default_conversion_cache
        return unless defined?(::Lutaml::Store::BasicStore)

        ::Lutaml::Store::BasicStore.new(adapter: { type: :memory })
      end
    end
  end
end
