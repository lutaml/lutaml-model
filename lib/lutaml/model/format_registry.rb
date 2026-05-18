# frozen_string_literal: true

module Lutaml
  module Model
    # Registry for serialization formats and their associated components.
    #
    # Manages the registration of formats (xml, json, yaml, etc.) and their
    # mapping classes, transformers, and adapter metadata. Adapter loading
    # and resolution is delegated to AdapterResolver.
    #
    class FormatRegistry
      class << self
        # Register a new format with its associated components.
        #
        # @param format [Symbol] the format name (e.g., :xml, :json)
        # @param mapping_class [Class] the mapping class for this format
        # @param adapter_class [Class, nil] the adapter class (nil for selectable formats)
        # @param transformer [Class] the transformer class for serialization
        # @param adapter_loader [Module, nil] optional module with load_adapter_file and class_for
        # @param castable_type [Class, nil] the castable type class
        # @param key_value [Boolean] whether this is a key-value format
        # @param error_types [Array<String, Class>] error types for this format
        # @param adapter_options [Hash, nil] { available: [...], default: :name }
        def register(format, mapping_class:, adapter_class:, transformer:,
                     adapter_loader: nil, castable_type: nil, key_value: nil,
                     rdf: nil, error_types: nil, adapter_options: nil)
          validate_registration!(format, mapping_class, transformer)

          registered_formats[format] = {
            mapping_class: mapping_class,
            transformer: transformer,
            adapter_class: adapter_class,
            adapter_loader: adapter_loader,
            castable_type: castable_type,
            key_value: key_value,
            rdf: rdf,
            error_types: error_types,
            adapter_options: adapter_options,
            registered_at: Time.now,
          }

          # Register type methods on model classes
          ::Lutaml::Model::Type::Value.register_format_to_from_methods(format)
          ::Lutaml::Model::Serialize.register_format_mapping_method(format)
          ::Lutaml::Model::Serialize.register_from_format_method(format)
          ::Lutaml::Model::Serialize.register_to_format_method(format)

          ::Lutaml::Model::Attribute.format_specific_warn_names.push(:"to_#{format}")

          # Register adapter metadata with AdapterResolver
          if adapter_options
            # Selectable adapters — have multiple options (xml, toml, json, yaml, hash)
            AdapterResolver.register_metadata(format, adapter_options)
          elsif adapter_class
            # Fixed adapter (jsonl, yamls) — register as sole available adapter
            adapter_name = derive_adapter_name(adapter_class)
            AdapterResolver.register_fixed(format, adapter_class, adapter_name)
          end

          # Define adapter type accessor methods on Config module
          ::Lutaml::Model::Config.define_adapter_type_methods(format)

          # Define adapter accessor methods on Configuration class
          define_configuration_adapter_methods(format, adapter_options)

          registered_formats[format]
        end

        def unregister(format)
          registered_formats.delete(format)
        end

        def registered?(format)
          registered_formats.key?(format)
        end

        def mappings_class_for(format)
          registered_formats.dig(format, :mapping_class)
        end

        def transformer_for(format)
          registered_formats.dig(format, :transformer)
        end

        def adapter_class_for(format)
          registered_formats.dig(format, :adapter_class)
        end

        def adapter_loader_for(format)
          registered_formats.dig(format, :adapter_loader)
        end

        def adapter_options_for(format)
          registered_formats.dig(format, :adapter_options)
        end

        def castable_type_for(format)
          registered_formats.dig(format, :castable_type)
        end

        def formats
          registered_formats.keys
        end

        def key_value_formats
          registered_formats.select { |_, info| info[:key_value] }.keys
        end

        def key_value?(format)
          registered_formats.dig(format, :key_value) == true
        end

        def rdf_formats
          registered_formats.select { |_, info| info[:rdf] }.keys
        end

        def rdf?(format)
          registered_formats.dig(format, :rdf) == true
        end

        def error_types_for(format)
          registered_formats.dig(format, :error_types)
        end

        def all_error_types
          registered_formats.values.filter_map do |info|
            info[:error_types]
          end.flatten.compact
        end

        def info(format)
          registered_formats[format]
        end

        def all
          registered_formats.dup
        end

        def reset!
          @registered_formats = nil
        end

        private

        def registered_formats
          @registered_formats ||= {}
        end

        def define_configuration_adapter_methods(format, adapter_options)
          cfg = ::Lutaml::Model::Configuration
          return if cfg.method_defined?(:"#{format}_adapter=")

          adapter_options&.dig(:default)

          # Adapter class getter on Configuration instance
          cfg.define_method(:"#{format}_adapter") do
            AdapterResolver.adapter_for(format)
          end

          # Adapter type name setter on Configuration instance
          cfg.define_method(:"#{format}_adapter=") do |adapter_type|
            set_adapter(format, adapter_type)
          end

          # Aliased _type methods
          cfg.class_eval do
            alias_method :"#{format}_adapter_type=", :"#{format}_adapter="
          end
          cfg.class_eval do
            alias_method :"#{format}_adapter_type", :"#{format}_adapter"
          end
        end

        # Derive a symbol adapter name from an adapter class.
        #
        # @param adapter_class [Class] e.g., Lutaml::Json::Adapter::StandardAdapter
        # @return [Symbol] e.g., :standard
        def derive_adapter_name(adapter_class)
          name = adapter_class.name
          return :standard unless name

          # Extract the adapter type from class name: "...::StandardAdapter" → :standard
          short = name.split("::").last
          short = short.delete_suffix("Adapter")
          short.downcase.to_sym
        end

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
