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
        def register(format, mapping_class:, adapter_class:, transformer:)
          validate_registration!(format, mapping_class, transformer)

          registered_formats[format] = {
            mapping_class: mapping_class,
            transformer: transformer,
            adapter_class: adapter_class,
            registered_at: Time.now,
          }

          ::Lutaml::Model::Type::Value.register_format_to_from_methods(format)
          ::Lutaml::Model::Serialize.register_format_mapping_method(format)
          ::Lutaml::Model::Serialize.register_from_format_method(format)
          ::Lutaml::Model::Serialize.register_to_format_method(format)

          Lutaml::Model::Config.set_adapter_for(format, adapter_class)

          # Always define adapter methods (even if adapter_class is nil)
          Lutaml::Model::Config.define_singleton_method(:"#{format}_adapter") do
            @adapters[format] || adapter_class
          end

          Lutaml::Model::Config.define_singleton_method(:"#{format}_adapter=") do |adapter_klass|
            @adapters ||= {}
            @adapters[format] = adapter_klass
          end

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

        # Get all registered format names
        #
        # @return [Array<Symbol>]
        def formats
          registered_formats.keys
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
