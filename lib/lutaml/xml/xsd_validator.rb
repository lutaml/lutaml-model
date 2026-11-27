# frozen_string_literal: true

require "concurrent" unless RUBY_ENGINE == "opal"

module Lutaml
  module Xml
    # Validates a serialized XML string against an XSD schema file.
    #
    # Backs the `validate_xml_with` class macro (issue #264). Routing is
    # engine-agnostic through moxml (#1184): schemas compile and validate
    # on the CONFIGURED engine — `Moxml::XSD.supported?` answers without
    # raising, and engines without a validator (ox, oga, rexml) fall back
    # to the historical Nokogiri path, keeping its requirement error when
    # the gem is absent. The leptris engine carries a validator.
    #
    # Strict parsing: libxml2 recovery would otherwise repair malformed
    # input and report it as schema-valid. Malformed input raises
    # Moxml::ParseError (the normalized class; line and column carried).
    #
    # Compiled schemas are memoized by absolute path: the XSD files are
    # constant for the life of the process, so each is read and compiled once
    # and reused across every validate / validate_xml call.
    #
    # Not to be confused with Schema::Xsd::SchemaValidator, which checks
    # that an XSD document itself is well-formed XSD.
    module XsdValidator
      @schemas = ::Concurrent::Map.new unless RUBY_ENGINE == "opal"
      @nokogiri_schemas = ::Concurrent::Map.new unless RUBY_ENGINE == "opal"

      # @param xml [String] an XML document
      # @param schema_paths [Array<String>] paths to XSD schema files
      # @return [Array<Error::SchemaValidationError>] one error per violation
      def self.validate(xml, schema_paths)
        paths = Array(schema_paths)
        return [] if paths.empty?

        if RUBY_ENGINE == "opal"
          raise NotImplementedError,
                "XSD schema validation (validate_xml_with) requires an " \
                "XML engine with schema validation, which is not " \
                "available under Opal."
        end

        if engine_supports_xsd?
          document = context.parse(xml, strict: true)
          paths.flat_map do |path|
            schema_for(path)
              .validate(document)
              .map { |error| Error::SchemaValidationError.new(error.message, path) }
          end
        else
          ensure_nokogiri!
          begin
            document = ::Nokogiri::XML(xml, &:strict)
          rescue ::Nokogiri::XML::SyntaxError => e
            # One error contract across lanes: the fallback normalizes
            # to the same Moxml::ParseError the engine path raises.
            raise Moxml::ParseError.new(e.message, line: e.line,
                                                   column: e.column)
          end
          paths.flat_map do |path|
            nokogiri_schema_for(path)
              .validate(document)
              .map { |error| Error::SchemaValidationError.new(error.message, path) }
          end
        end
      end

      # The configured engine as a moxml backend symbol. Config's plain
      # symbol (nokogiri, leptris, ...) — NOT the AdapterResolver's
      # configured type, whose FIXED_ADAPTER_TYPE sentinel is internal
      # and must never reach Moxml (the closed #1183 leak).
      def self.backend
        Lutaml::Xml.moxml_engine
      end

      def self.engine_supports_xsd?
        Moxml::XSD.supported?(context)
      rescue Moxml::AdapterError, LoadError
        false
      end

      def self.context
        @context ||= Moxml.new(backend)
      end

      def self.schema_for(path)
        @schemas.compute_if_absent(path) do
          # One error contract across lanes: engines with file-based
          # compilation (leptris) read the schema themselves and would
          # surface their own error for a missing path; checking here
          # keeps the missing-schema case a plain Errno::ENOENT on
          # every engine.
          raise Errno::ENOENT, path unless File.exist?(path)

          context.xsd_file(path)
        end
      end

      def self.ensure_nokogiri!
        require "nokogiri"
      rescue LoadError
        raise Error::XmlConfigurationError,
              "XSD schema validation (validate_xml_with) requires an " \
              "XML engine with schema validation; add `gem \"nokogiri\"` " \
              "to your Gemfile"
      end

      def self.nokogiri_schema_for(path)
        @nokogiri_schemas.compute_if_absent(path) do
          ::Nokogiri::XML::Schema(File.read(path))
        end
      end

      private_class_method :ensure_nokogiri!, :nokogiri_schema_for
    end
  end
end
