# frozen_string_literal: true

require "rexml/document"

module Lutaml
  module Xml
    module Adapter
      # Class methods for parsing XML input.
      #
      # Extracted from BaseAdapter — parsing is a distinct lifecycle phase
      # with no instance state dependency.
      #
      # Subclasses must define:
      # - MOXML_ADAPTER — Moxml adapter class for parsing
      # - PARSED_ELEMENT_CLASS — element wrapper class
      # - PARSE_ERROR_CLASS — error class to rescue (nil to skip)
      # - EMPTY_DOCUMENT_ERROR_MESSAGE — error message for empty docs
      # - EMPTY_DOCUMENT_ERROR_TYPE — :invalid_format or :parse_exception
      module XmlParsing
        def parse(xml, options = {})
          parse_encoding = encoding(xml, options)
          raw_xml = xml
          xml = normalize_xml_for_parse(xml)
          parsed = parse_with_moxml(xml, parse_encoding)
          root_element = parsed.root

          raise_empty_document_error if root_element.nil?

          root = self::PARSED_ELEMENT_CLASS.new(root_element)
          new(root, parse_encoding, **parse_document_options(raw_xml))
        end

        def normalize_xml_for_parse(xml)
          return xml unless xml.is_a?(String)
          return xml if xml.encoding == Encoding::UTF_8 && xml.valid_encoding?

          if xml.encoding == Encoding::ASCII_8BIT
            normalized_xml = xml.dup
            normalized_xml.force_encoding(Encoding::UTF_8)
            return normalized_xml if normalized_xml.valid_encoding?
          end

          xml.encode(Encoding::UTF_8,
                     invalid: :replace,
                     undef: :replace,
                     replace: "?")
        end

        def parse_with_moxml(xml, parse_encoding)
          parse_error_class = self::PARSE_ERROR_CLASS
          return self::MOXML_ADAPTER.parse(xml, encoding: parse_encoding) unless parse_error_class

          begin
            self::MOXML_ADAPTER.parse(xml, encoding: parse_encoding)
          rescue parse_error_class => e
            raise Lutaml::Model::InvalidFormatError.new(:xml, e.message)
          end
        end

        def parse_document_options(xml)
          {
            doctype: extract_doctype_from_xml(xml),
            xml_declaration: DeclarationHandler.extract_xml_declaration(xml),
          }
        end

        def raise_empty_document_error
          message = self::EMPTY_DOCUMENT_ERROR_MESSAGE

          case self::EMPTY_DOCUMENT_ERROR_TYPE
          when :parse_exception
            raise REXML::ParseException.new(message)
          else
            raise Lutaml::Model::InvalidFormatError.new(:xml, message)
          end
        end
      end
    end
  end
end
