# frozen_string_literal: true

require_relative "../namespace"

module Lutaml
  module Xml
    module Schema
      # W3C XML Schema Definition (XSD) Namespace
      #
      # Standard namespace for XSD schema elements and types.
      # Used by all XSD model classes for proper XML serialization.
      #
      # @see https://www.w3.org/2001/XMLSchema
      class XsdNamespace < Lutaml::Xml::Namespace
        uri "http://www.w3.org/2001/XMLSchema"
        prefix_default "xsd"

        documentation <<~DOC
          W3C XML Schema namespace for XSD definitions.

          This namespace is used by all XSD schema elements including:
          - Schema structure elements (element, complexType, simpleType, etc.)
          - Built-in data types (string, integer, date, etc.)
          - Schema composition rules (sequence, choice, group, etc.)
        DOC
      end
    end
  end
end
