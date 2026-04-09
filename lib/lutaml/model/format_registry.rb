# frozen_string_literal: true

module Lutaml
  module Model
    # Registry for serialization formats and their associated components
    #
    # This class manages the registration of formats (xml, json, yaml, etc.)
    # and their associated mapping classes, adapters, and transformers.
    #
    # @example Registering a custom format
    #   Lutaml::Model::FormatRegistry.register(:custom,
    #     mapping_class: MyMapping,
    #     adapter_class: MyAdapter,
    #     transformer: MyTransformer
    #   )
    #
    # @example Checking if a format is registered
    #   Lutaml::Model::FormatRegistry.registered?(:xml) #=> true
    #
    # @example Listing all registered formats
    #   Lutaml::Model::FormatRegistry.formats #=> [:xml, :json, :yaml, ...]
    #
    class FormatRegistry
      class << self
        # Register a new format with its associated components
        #
        # @param format [Symbol] the format name (e.g., :xml, :json)
        # @param mapping_class [Class] the mapping class for this format
        # @param adapter_class [Class, nil] the adapter class (nil for abstract formats)
        # @param transformer [Class] the transformer class for serialization
        # @raise [ArgumentError] if format is invalid or required params missing
        # @return [Hash] the registered format configuration
        # @param adapter_loader [Module, nil] optional module with load_adapter_file and class_for methods
        def register(format, mapping_class:, adapter_class:, transformer:,
adapter_loader: nil, castable_type: nil, key_value: nil, error_types: nil, adapter_options: nil)
          validate_registration!(format, mapping_class, transformer)

          registered_formats[format] = {
            mapping_class: mapping_class,
            transformer: transformer,
            adapter_class: adapter_class,
            adapter_loader: adapter_loader,
            castable_type: castable_type,
            key_value: key_value,
            error_types: error_types,
            adapter_options: adapter_options,
            registered_at: Time.now,
          }

          ::Lutaml::Model::Type::Value.register_format_to_from_methods(format)
          ::Lutaml::Model::Serialize.register_format_mapping_method(format)
          ::Lutaml::Model::Serialize.register_from_format_method(format)
          ::Lutaml::Model::Serialize.register_to_format_method(format)

          # Push format-specific serialization method name to warn list
          ::Lutaml::Model::Attribute.format_specific_warn_names.push(:"to_#{format}")

          Lutaml::Model::Config.set_adapter_for(format, adapter_class)

          # Define raw adapter getter/setter on Config module
          Lutaml::Model::Config.define_singleton_method(:"#{format}_adapter") do
            @adapters[format] || adapter_class
          end

          Lutaml::Model::Config.define_singleton_method(:"#{format}_adapter=") do |adapter_klass|
            @adapters ||= {}
            @adapters[format] = adapter_klass
          end

          # Define _type suffixed methods on Config module (delegate to Configuration#set_adapter)
          Lutaml::Model::Config.define_singleton_method(:"#{format}_adapter_type=") do |type_name|
            instance.set_adapter(format, type_name)
          end

          Lutaml::Model::Config.define_singleton_method(:"#{format}_adapter_type") do
            instance.adapter_for(format)
          end

          # Define adapter methods on Configuration class for this format
          define_configuration_adapter_methods(format, adapter_options)

          registered_formats[format]
        end

        # Unregister a format
        #
        # @param format [Symbol] the format to unregister
        # @return [Hash, nil] the removed format configuration or nil if not found
        def unregister(format)
          registered_formats.delete(format)
        end

        # Check if a format is registered
        #
        # @param format [Symbol] the format to check
        # @return [Boolean]
        def registered?(format)
          registered_formats.key?(format)
        end

        # Get the mapping class for a format
        #
        # @param format [Symbol] the format name
        # @return [Class, nil] the mapping class or nil if not registered
        def mappings_class_for(format)
          registered_formats.dig(format, :mapping_class)
        end

        # Get the transformer for a format
        #
        # @param format [Symbol] the format name
        # @return [Class, nil] the transformer class or nil if not registered
        def transformer_for(format)
          registered_formats.dig(format, :transformer)
        end

        # Get the adapter class for a format
        #
        # @param format [Symbol] the format name
        # @return [Class, nil] the adapter class or nil if not registered
        def adapter_class_for(format)
          registered_formats.dig(format, :adapter_class)
        end

        # Get the adapter loader for a format
        #
        # @param format [Symbol] the format name
        # @return [Module, nil] the adapter loader or nil
        def adapter_loader_for(format)
          registered_formats.dig(format, :adapter_loader)
        end

        # Get the adapter options for a format
        #
        # @param format [Symbol] the format name
        # @return [Hash, nil] { available: [...], default: :name } or nil
        def adapter_options_for(format)
          registered_formats.dig(format, :adapter_options)
        end

        # Get the castable type for a format
        #
        # @param format [Symbol] the format name
        # @return [Class, nil] the castable type or nil
        def castable_type_for(format)
          registered_formats.dig(format, :castable_type)
        end

        # Get all registered format names
        #
        # @return [Array<Symbol>]
        def formats
          registered_formats.keys
        end

        # Get all key-value format names (non-XML formats)
        #
        # @return [Array<Symbol>]
        def key_value_formats
          registered_formats.select { |_, info| info[:key_value] }.keys
        end

        # Check if a format is a key-value format
        #
        # @param format [Symbol] the format name
        # @return [Boolean]
        def key_value?(format)
          registered_formats.dig(format, :key_value) == true
        end

        # Get format-specific error types
        #
        # @param format [Symbol] the format name
        # @return [Array<Class>, nil] error types for this format
        def error_types_for(format)
          registered_formats.dig(format, :error_types)
        end

        # Get all registered error types across all formats
        #
        # @return [Array<Class>]
        def all_error_types
          registered_formats.values.filter_map do |info|
            info[:error_types]
          end.flatten.compact
        end

        # Get registration info for a format
        #
        # @param format [Symbol] the format name
        # @return [Hash, nil] the registration info or nil if not found
        def info(format)
          registered_formats[format]
        end

        # Get all registered formats with their details
        #
        # @return [Hash{Symbol => Hash}]
        def all
          registered_formats.dup
        end

        # Reset the registry (primarily for testing)
        #
        # @return [void]
        def reset!
          @registered_formats = nil
        end

        private

        # Get the internal registry hash
        #
        # @return [Hash]
        def registered_formats
          @registered_formats ||= {}
        end

        # Define adapter getter/setter methods on Configuration class
        # for a dynamically registered format.
        #
        # @param format [Symbol] the format name
        # @param adapter_options [Hash, nil] { available: [...], default: :name }
        def define_configuration_adapter_methods(format, adapter_options)
          cfg = ::Lutaml::Model::Configuration
          return if cfg.method_defined?(:"#{format}_adapter")

          default_adapter = adapter_options&.dig(:default)

          cfg.define_method(:"#{format}_adapter") do
            @adapter_types[format] || default_adapter
          end

          cfg.define_method(:"#{format}_adapter=") do |adapter_type|
            set_adapter(format, adapter_type)
          end

          cfg.send(:alias_method, :"#{format}_adapter_type=",
                   :"#{format}_adapter=")
          cfg.send(:alias_method, :"#{format}_adapter_type",
                   :"#{format}_adapter")
        end

        # Validate registration parameters
        #
        # @param format [Symbol] the format name
        # @param mapping_class [Class] the mapping class
        # @param transformer [Class] the transformer class
        # @raise [ArgumentError] if validation fails
        def validate_registration!(format, mapping_class, transformer)
          unless format.is_a?(Symbol)
            raise ArgumentError,
                  "Format must be a Symbol, got #{format.class}: #{format.inspect}"
          end

          if format.to_s.empty?
            raise ArgumentError, "Format cannot be empty"
          end

          unless mapping_class.is_a?(Class)
            raise ArgumentError,
                  "mapping_class must be a Class, got #{mapping_class.class}"
          end

          unless transformer.is_a?(Class)
            raise ArgumentError,
                  "transformer must be a Class, got #{transformer.class}"
          end

          if registered?(format)
            warn "[Lutaml::Model] WARNING: Re-registering format :#{format}. " \
                 "This may cause unexpected behavior."
          end
        end
      end
    end
  end
end
