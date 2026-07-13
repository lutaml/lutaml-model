# frozen_string_literal: true

module Lutaml
  module Xml
    module Error
      # Collected when a model's generated XML does not conform to the
      # XSD schema configured via the `validate_xml_with` macro.
      #
      # One instance represents one schema violation reported by the
      # validating parser, so Lutaml::Model::ValidationError#error_messages
      # lists each violation individually.
      #
      # Not to be confused with Schema::Xsd::SchemaValidationError, which
      # reports problems in an XSD document itself.
      class SchemaValidationError < XmlError
        attr_reader :schema_path

        def initialize(message, schema_path)
          @schema_path = schema_path
          super("XML does not conform to schema #{schema_path}: #{message}")
        end
      end
    end
  end
end
