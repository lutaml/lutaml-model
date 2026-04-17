# frozen_string_literal: true

module Lutaml
  module Model
    module Serialize
      # Handles format conversion methods for Serialize::ClassMethods
      #
      # Extracted from serialize.rb to improve code organization.
      # Provides methods for serializing/deserializing between formats.
      module FormatConversion
        # Process mapping DSL for a format
        #
        # @param format [Symbol] The format (:xml, :json, etc.)
        # @param args [Array] Additional arguments (e.g., mapping class for XML)
        # @param block [Proc] The DSL block to evaluate
        def process_mapping(format, *_args, &)
          klass = ::Lutaml::Model::Config.mappings_class_for(format)
          mappings[format] ||= klass.new
          mappings[format].instance_eval(&)

          if mappings[format].respond_to?(:finalize)
            mappings[format].finalize(self)
          end

          post_process_mapping(format)
        end

        # Hook for format-specific post-processing after mapping DSL evaluation.
        # XML overrides this to call check_sort_configs!.
        #
        # @param _format [Symbol] The format
        def post_process_mapping(_format)
          # No-op by default; XML overrides via prepend
        end

        # Deserialize from a format
        #
        # @param format [Symbol] The format to deserialize from
        # @param data [String, Object] The data to deserialize
        # @param options [Hash] Additional options
        # @return [Object] The deserialized model instance
        def from(format, data, options = {})
          Instrumentation.instrument(:from, model: name, format: format) do
            adapter = Lutaml::Model::Config.adapter_for(format)

            raise Lutaml::Model::FormatAdapterNotSpecifiedError.new(format) if adapter.nil?

            # Resolve imports at the entry point of deserialization
            register = options[:register] || Lutaml::Model::Config.default_register

            # Hook for format-specific pre-deserialization (e.g., XML mapping import resolution)
            pre_deserialize_hook(format, register)

            # Recursively resolve child model imports
            # This ensures the entire model tree is finalized before parsing
            ensure_child_imports_resolved!(register)

            doc = if format == :xml && Lutaml::Model::Config.instance.xml_parse_mode != :dom && adapter.respond_to?(:parse_sax)
                    adapter.parse_sax(data, options)
                  else
                    adapter.parse(data, options)
                  end
            send("of_#{format}", doc, options)
          end
        rescue *format_error_types => e
          raise Lutaml::Model::InvalidFormatError.new(format, e.message)
        end

        # Hook for format-specific pre-deserialization logic.
        # XML overrides to resolve XML mapping imports.
        #
        # @param _format [Symbol] The format
        # @param _register [Symbol] The register
        def pre_deserialize_hook(_format, _register)
          # No-op by default; XML overrides via prepend
        end

        # Get list of error types that can be raised during format parsing.
        # Core errors are always included; format-specific errors come from
        # FormatRegistry registrations.
        #
        # @return [Array<Class>] List of error classes
        def format_error_types
          errors = [
            Psych::SyntaxError,
            JSON::ParserError,
            NoMethodError,
            TypeError,
            ArgumentError,
          ]

          # SAX parsing raises Moxml::ParseError for invalid XML
          if Object.const_defined?("Moxml::ParseError")
            errors << Moxml::ParseError
          end

          # Collect format-specific error types from FormatRegistry
          FormatRegistry.all.each_value do |info|
            next unless info[:error_types]

            info[:error_types].each do |error_class|
              cls = error_class.is_a?(String) ? safe_get_const(error_class) : error_class
              errors << cls
            end
          end

          # Legacy TOML error types (key-value formats without explicit registration)
          %w[
            TomlRB::ParseError
            Tomlib::ParseError
          ].each do |error_class|
            errors << safe_get_const(error_class)
          end

          errors.compact
        end

        # Safely get a constant by name
        #
        # @param error_class [String] The constant name
        # @return [Class, nil] The constant or nil if not defined
        def safe_get_const(error_class)
          return unless Object.const_defined?(error_class.split("::").first)

          error_class.split("::").inject(Object) do |mod, part|
            mod.const_get(part)
          end
        end

        # Create a model instance from a parsed document
        #
        # @param format [Symbol] The format
        # @param doc [Object] The parsed document
        # @param options [Hash] Additional options
        # @return [Object] The model instance
        def of(format, doc, options = {})
          if doc.is_a?(Array) && format != :jsonl
            return doc.map { |item| send(:"of_#{format}", item) }
          end

          register = extract_register_id(options[:register])

          # Hook for format-specific document validation (e.g., XML root/encoding/doctype)
          validate_document(format, doc, options, register)

          options[:register] = register

          transformer = Lutaml::Model::Config.transformer_for(format)
          transformer.data_to_model(self, doc, format, options)
        end

        # Hook for format-specific document validation.
        # XML overrides to validate root mapping and extract encoding/doctype.
        #
        # @param _format [Symbol] The format
        # @param _doc [Object] The parsed document
        # @param _options [Hash] Options hash (may be modified)
        # @param _register [Symbol] The register
        def validate_document(_format, _doc, _options, _register)
          # No-op by default; XML overrides via prepend
        end

        # Serialize a model instance to a format
        #
        # @param format [Symbol] The format to serialize to
        # @param instance [Object] The model instance
        # @param options [Hash] Additional options
        # @option options [Symbol, String, Boolean] :prefix XML namespace prefix control
        #   - nil (default): Preserve input format during round-trip
        #   - true: Force prefix format using namespace's prefix_default
        #   - :default: Force default namespace format (no prefix on element)
        #   - String: Use custom prefix string (e.g., 'custom')
        #   For round-trip fidelity, the original namespace URI (alias or canonical)
        #   is always preserved when available, regardless of this option.
        # @return [String] The serialized output
        def to(format, instance, options = {})
          Instrumentation.instrument(:to, model: name, format: format) do
            value = public_send(:"as_#{format}", instance, options)
            adapter = Lutaml::Model::Config.adapter_for(format)

            # Hook for format-specific options preparation (e.g., XML prefix/namespace/declaration)
            options = prepare_to_options(format, instance, options)

            adapter.new(value, register: options[:register]).public_send(
              :"to_#{format}", options
            )
          end
        end

        # Hook for format-specific options preparation before serialization.
        # XML overrides to handle prefix, namespace overrides, declaration plan.
        #
        # @param _format [Symbol] The format
        # @param _instance [Object] The model instance
        # @param options [Hash] The options hash
        # @return [Hash] The modified options hash
        def prepare_to_options(_format, _instance, options)
          options
        end

        # Convert a model instance to format-specific data structure
        #
        # @param format [Symbol] The format
        # @param instance [Object] The model instance
        # @param options [Hash] Additional options
        # @return [Object] The format-specific data structure
        def as(format, instance, options = {})
          if instance.is_a?(Array)
            return instance.map { |item| public_send(:"as_#{format}", item) }
          end

          unless instance.is_a?(model)
            msg = "argument is a '#{instance.class}' but should be a '#{model}'"
            raise Lutaml::Model::IncorrectModelError, msg
          end

          # Resolve imports at the start of serialization
          register = options[:register] || Lutaml::Model::Config.default_register

          # Hook for format-specific pre-serialization (e.g., XML mapping import resolution)
          pre_serialize_hook(format, register)

          # Recursively resolve child model imports
          ensure_child_imports_resolved!(register)

          transformer = Lutaml::Model::Config.transformer_for(format)
          transformer.model_to_data(self, instance, format, options)
        end

        # Hook for format-specific pre-serialization logic.
        # XML overrides to resolve XML mapping imports.
        #
        # @param _format [Symbol] The format
        # @param _register [Symbol] The register
        def pre_serialize_hook(_format, _register)
          # No-op by default; XML overrides via prepend
        end

        # Define key-value mappings for multiple formats.
        # Uses FormatRegistry to discover key-value formats dynamically,
        # falling back to Config::KEY_VALUE_FORMATS for bootstrap.
        #
        # @param block [Proc] The DSL block
        def key_value(&block)
          formats = if FormatRegistry.formats.any?
                      FormatRegistry.key_value_formats
                    else
                      Lutaml::Model::Config::KEY_VALUE_FORMATS
                    end

          formats.each do |format|
            mappings[format] ||= Lutaml::KeyValue::Mapping.new(format)
            mappings[format].instance_eval(&block)
            mappings[format].finalize(self)
          end
        end

        # Get resolved mapping for a format
        #
        # Delegates to TransformationRegistry for centralized caching
        # (Single Source of Truth - Phase 11.5).
        #
        # @param format [Symbol] The format (:xml, :json, :yaml, :toml, :hash)
        # @param register [Symbol, Register, nil] The register for import resolution
        # @return [Mapping, nil] The resolved mapping or nil
        def mappings_for(format, register = nil)
          TransformationRegistry.instance.get_or_build_mapping(self, format,
                                                               register)
        end

        # Generate default mappings for a format
        #
        # @param format [Symbol] The format
        # @return [Mapping] The default mapping
        def default_mappings(format)
          klass = ::Lutaml::Model::Config.mappings_class_for(format)
          mappings = klass.new

          mappings.tap do |mapping|
            attributes&.each_key do |name|
              mapping.map_element(
                name.to_s,
                to: name,
              )
            end

            # DO NOT auto-generate root element for XML
            # Models without an explicit xml block should be type-only models
            # If a root element is needed, declare it explicitly in xml block
          end
        end
      end
    end
  end
end
