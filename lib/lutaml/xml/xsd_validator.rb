# frozen_string_literal: true

require "concurrent"

module Lutaml
  module Xml
    # Validates a serialized XML string against an XSD schema file.
    #
    # Backs the `validate_xml_with` class macro (issue #264). Nokogiri is
    # required lazily so models that do not use XSD validation keep working
    # on platforms/adapters without it (Opal, ox-only installs).
    #
    # Compiled schemas are memoized by absolute path: the XSD files are
    # constant for the life of the process, so each is read and compiled once
    # and reused across every validate / validate_xml call.
    #
    # Not to be confused with Schema::Xsd::SchemaValidator, which checks
    # that an XSD document itself is well-formed XSD.
    module XsdValidator
      @schemas = ::Concurrent::Map.new

      # @param xml [String] an XML document
      # @param schema_paths [Array<String>] paths to XSD schema files
      # @return [Array<Error::SchemaValidationError>] one error per violation
      def self.validate(xml, schema_paths)
        paths = Array(schema_paths)
        return [] if paths.empty?

        ensure_nokogiri!
        # Strict parsing: libxml2 recovery would otherwise repair malformed
        # input and report it as schema-valid. NONET remains on by default.
        document = ::Nokogiri::XML(xml, &:strict)
        paths.flat_map do |path|
          schema_for(path)
            .validate(document)
            .map { |error| Error::SchemaValidationError.new(error.message, path) }
        end
      end

      def self.schema_for(path)
        @schemas.compute_if_absent(path) do
          ::Nokogiri::XML::Schema(File.read(path))
        end
      end

      def self.ensure_nokogiri!
        require "nokogiri"
      rescue LoadError
        raise Error::XmlConfigurationError,
              "XSD schema validation (validate_xml_with) requires the " \
              "nokogiri gem; add `gem \"nokogiri\"` to your Gemfile"
      end

      private_class_method :ensure_nokogiri!, :schema_for
    end
  end
end
