# frozen_string_literal: true

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
      module XmlParser
        def parse(xml, options = {})
          parse_encoding = encoding(xml, options)
          raw_xml = xml
          xml = normalize_xml_for_parse(xml)
          parsed = parse_with_moxml(xml, parse_encoding)
          assert_no_truncated_recovered_parse!(parsed)
          root_element = parsed.root

          raise_empty_document_error if root_element.nil?

          root = self::PARSED_ELEMENT_CLASS.new(root_element)
          doc_pis = extract_document_processing_instructions(parsed)
          root.processing_instructions = doc_pis unless doc_pis.empty?
          new(root, parse_encoding, **parse_document_options(raw_xml))
        end

        # Recover-mode parsing must never masquerade input truncation as
        # success.
        #
        # moxml releases before 0.5.84 parsed Nokogiri documents without
        # XML_PARSE_HUGE, so libxml2 capped its input buffer at 10 MB;
        # longer documents tripped a fatal "Resource limit exceeded:
        # Buffer size limit exceeded, try XML_PARSE_HUGE" error mid-input.
        # In recover mode Nokogiri records that error on the document and
        # returns the partial tree, so every node past the limit silently
        # vanishes (lutaml-model#871). A resource-limit fatal means the
        # engine stopped early with input left — refuse to deserialize the
        # partial document instead of dropping trailing content without a
        # trace.
        #
        # moxml 0.5.84 and later always pass XML_PARSE_HUGE, so the
        # Nokogiri path no longer truncates and this guard stays silent;
        # it remains for older moxml releases and for any other adapter
        # that reports the resource-limit family.
        #
        # Other recover-mode fatals (e.g. an XML declaration after leading
        # whitespace) do not drop content and keep the long-standing
        # recover behavior; only the resource-limit family is truncating.
        TRUNCATION_FATAL_MARKER =
          /Resource limit exceeded|Buffer size limit exceeded/

        private

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
          unless parse_error_class
            return self::MOXML_ADAPTER.parse(xml,
                                             encoding: parse_encoding)
          end

          begin
            self::MOXML_ADAPTER.parse(xml, encoding: parse_encoding)
          rescue parse_error_class => e
            raise Lutaml::Model::InvalidFormatError.new(:xml, e.message)
          end
        end

        def assert_no_truncated_recovered_parse!(parsed)
          errors = parsed.parse_errors
          return if errors.nil? || errors.empty?

          fatal = errors.find do |message|
            message.match?(TRUNCATION_FATAL_MARKER)
          end
          return if fatal.nil?

          raise Lutaml::Model::InvalidFormatError.new(
            :xml,
            "the XML engine reported a fatal resource limit and recovered " \
            "with a truncated document; refusing to deserialize " \
            "partial input (#{fatal})",
          )
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
            require "rexml/document"
            raise REXML::ParseException.new(message)
          else
            raise Lutaml::Model::InvalidFormatError.new(:xml, message)
          end
        end
      end
    end
  end
end
