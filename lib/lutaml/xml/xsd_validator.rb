# frozen_string_literal: true

require "concurrent" unless RUBY_ENGINE == "opal"
require "moxml" unless RUBY_ENGINE == "opal"

module Lutaml
  module Xml
    # Validates a serialized XML string against an XSD schema file.
    #
    # Backs the `validate_xml_with` class macro (issue #264). Validation
    # rides the moxml XSD layer, engine-agnostic (leptris whenever
    # present), so models that do not use XSD validation keep working
    # on platforms/adapters without a validator engine (Opal).
    #
    # Compiled schemas are memoized by absolute path: the XSD files are
    # constant for the life of the process, so each is read and compiled once
    # and reused across every validate / validate_xml call.
    #
    # Not to be confused with Schema::Xsd::SchemaValidator, which checks
    # that an XSD document itself is well-formed XSD.
    module XsdValidator
      # A moxml context (and its validation engines) is unavailable under
      # Opal, so the memoization store is only built off-Opal. validate
      # raises a clear NotImplementedError under Opal before this store
      # is ever consulted.
      @schemas = ::Concurrent::Map.new unless RUBY_ENGINE == "opal"

      # @param xml [String] an XML document
      # @param schema_paths [Array<String>] paths to XSD schema files
      # @return [Array<Error::SchemaValidationError>] one error per violation
      def self.validate(xml, schema_paths)
        paths = Array(schema_paths)
        return [] if paths.empty?

        if RUBY_ENGINE == "opal"
          raise NotImplementedError,
                "XSD schema validation (validate_xml_with) requires an " \
                "XML engine with a schema validator, which is not " \
                "available under Opal."
        end

        # The configured XML engine decides the lane (the :nokogiri
        # engine remains fully supported); both lanes carry an XSD
        # compiler through moxml.
        engine = Lutaml::Model::Config.xml_adapter_type

        # Strict pre-parse: engine recovery would otherwise repair
        # malformed input and report it as schema-valid. The parse
        # error surfaces to the caller as Moxml::ParseError.
        Moxml.new(engine) do |config|
          config.strict_parsing = true
        end.parse(xml)

        # Per-validate context: the engine resolves xs:include against
        # each schema file's directory (Context#xsd_file face).
        context = Moxml.new(engine)
        paths.flat_map do |path|
          schema_for(context, path)
            .validate(xml)
            .map { |error| Error::SchemaValidationError.new(error.message, path) }
        end
      end

      def self.schema_for(context, path)
        @schemas.compute_if_absent(path) do
          # Read before the engine touches the path: a missing schema
          # file is a configuration error (Errno::ENOENT), not an
          # engine-level failure.
          File.read(path)
          context.xsd_file(path)
        end
      end

      private_class_method :schema_for
    end
  end
end
