# frozen_string_literal: true

module Lutaml
  module Xml
    # Validates a serialized XML string against an XSD schema file.
    #
    # Backs the `validate_xml_with` class macro (issue #264). Nokogiri is
    # required lazily so models that do not use XSD validation keep working
    # on platforms/adapters without it (Opal, ox-only installs).
    #
    # Not to be confused with Schema::Xsd::SchemaValidator, which checks
    # that an XSD document itself is well-formed XSD.
    module XsdValidator
      # @param xml [String] an XML document
      # @param schema_paths [Array<String>] paths to XSD schema files
      # @return [Array<Error::SchemaValidationError>] one error per violation
      def self.validate(xml, schema_paths)
        paths = Array(schema_paths)
        return [] if paths.empty?

        ensure_nokogiri!
        document = ::Nokogiri::XML(xml)
        paths.flat_map do |path|
          ::Nokogiri::XML::Schema(File.read(path))
            .validate(document)
            .map { |error| Error::SchemaValidationError.new(error.message, path) }
        end
      end

      def self.ensure_nokogiri!
        require "nokogiri"
      rescue LoadError
        raise Error::XmlConfigurationError,
              "XSD schema validation (validate_xml_with) requires the " \
              "nokogiri gem; add `gem \"nokogiri\"` to your Gemfile"
      end

      private_class_method :ensure_nokogiri!
    end
  end
end
