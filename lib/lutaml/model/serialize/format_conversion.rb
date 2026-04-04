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
        # @param block [Proc] The DSL block to evaluate
        def process_mapping(format, &)
          klass = ::Lutaml::Model::Config.mappings_class_for(format)
          mappings[format] ||= klass.new
          mappings[format].instance_eval(&)

          if mappings[format].respond_to?(:finalize)
            mappings[format].finalize(self)
          end

          check_sort_configs! if format == :xml
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

            # CRITICAL: Resolve ALL imports at the ENTRY POINT of deserialization
            # This ensures symbol-based imports registered after class definition are resolved
            # before we start parsing the document
            register = options[:register] || Lutaml::Model::Config.default_register
            if format == :xml && mappings[:xml]
              mappings[:xml].ensure_mappings_imported!(register)
            end

            # Recursively resolve child model imports
            # This ensures the entire model tree is finalized before parsing
            ensure_child_imports_resolved!(register)

            doc = adapter.parse(data, options)
            send("of_#{format}", doc, options)
          end
        rescue *format_error_types => e
          raise Lutaml::Model::InvalidFormatError.new(format, e.message)
        end

        # Get list of error types that can be raised during format parsing
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

          %w[
            Nokogiri::XML::SyntaxError
            Ox::ParseError
            REXML::ParseException
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
          if format == :xml
            valid = root?(register) || options[:from_collection]
            raise Lutaml::Model::NoRootMappingError.new(self) unless valid

            options[:encoding] = doc.encoding
            if doc.respond_to?(:doctype) && doc.doctype
              options[:doctype] =
                doc.doctype
            end
          end
          options[:register] = register

          transformer = Lutaml::Model::Config.transformer_for(format)
          transformer.data_to_model(self, doc, format, options)
        end

        # Serialize a model instance to a format
        #
        # @param format [Symbol] The format to serialize to
        # @param instance [Object] The model instance
        # @param options [Hash] Additional options
        # @return [String] The serialized output
        def to(format, instance, options = {})
          Instrumentation.instrument(:to, model: name, format: format) do
            value = public_send(:"as_#{format}", instance, options)
            adapter = Lutaml::Model::Config.adapter_for(format)

            options[:mapper_class] = self if format == :xml

            # Handle prefix option for XML
            if format == :xml && options.key?(:prefix)
              prefix_option = options[:prefix]
              mappings_for(:xml)

              case prefix_option
              when true
                # Force prefix format for all namespaces
                # Each namespace uses its own prefix_default
                options[:use_prefix] = true
              when String
                # Use specific custom prefix
                options[:use_prefix] = prefix_option
              when false, :default
                # Explicitly force default format (disable format preservation)
                options[:use_prefix] = false
              end
              # If prefix_option is nil, don't set use_prefix (allow format preservation)
              options.delete(:prefix) # Remove original option
            end

            # Apply namespace prefix overrides for XML format
            if format == :xml && options[:namespaces]
              options = apply_namespace_overrides(options)
            end

            # Retrieve stored declaration plan from model instance for namespace preservation.
            # This plan captures the original namespace declarations from the parsed XML,
            # enabling round-trip fidelity for unused namespaces (like xmlns:xi for XInclude).
            if format == :xml && instance.respond_to?(:xml_declaration_plan) &&
                !options.key?(:stored_xml_declaration_plan)
              stored_plan = instance.xml_declaration_plan
              options[:stored_xml_declaration_plan] = stored_plan if stored_plan
            end

            adapter.new(value, register: options[:register]).public_send(
              :"to_#{format}", options
            )
          end
        end

        # Apply namespace prefix overrides for XML serialization
        #
        # @param options [Hash] The options hash
        # @return [Hash] The modified options hash
        def apply_namespace_overrides(options)
          namespaces = options[:namespaces]
          return options unless namespaces.is_a?(Array)

          # Build a namespace URI to prefix mapping
          ns_prefix_map = {}
          namespaces.each do |ns_config|
            if ns_config.is_a?(Hash)
              ns_class = ns_config[:namespace]
              prefix = ns_config[:prefix]

              if ns_class.is_a?(Class) && ns_class < Lutaml::Xml::Namespace && prefix
                ns_prefix_map[ns_class.uri] = prefix.to_s
              end
            end
          end

          unless ns_prefix_map.empty?
            options[:namespace_prefix_map] =
              ns_prefix_map
          end
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

          # CRITICAL: Resolve ALL imports at the START of serialization
          # This ensures symbol-based imports registered after class definition are resolved
          # before we start building the document, without triggering infinite loops
          register = options[:register] || Lutaml::Model::Config.default_register

          # Resolve top-level mapping imports
          if format == :xml && mappings[:xml]
            mappings[:xml].ensure_mappings_imported!(register)
          end

          # Recursively resolve child model imports
          # This ensures the entire model tree is finalized before serialization
          ensure_child_imports_resolved!(register)

          transformer = Lutaml::Model::Config.transformer_for(format)
          transformer.model_to_data(self, instance, format, options)
        end

        # Define key-value mappings for multiple formats
        #
        # @param block [Proc] The DSL block
        def key_value(&block)
          Lutaml::Model::Config::KEY_VALUE_FORMATS.each do |format|
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
