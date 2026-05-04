# frozen_string_literal: true

module Lutaml
  module Xml
    module Adapter
      # Post-processes XML strings for OOXML format compliance.
      #
      # Handles two normalization rules:
      # 1. Boolean elements: <w:elem w:val="true"/> -> <w:elem/>
      # 2. XML namespace attribute: <w:t w:xml:space=...> -> <w:t xml:space=...>
      module OoxmlFormatter
        # OOXML boolean element names: self-closing elements where presence = true.
        # Whitelist of known boolean element names to avoid incorrectly
        # transforming non-boolean elements like numId, colSpan, etc.
        OOXML_BOOLEAN_ELEMENTS = %w[
          b i strike bCs iCs smallCaps caps vanish noProof
          shadow emboss imprint keepNext keepLines outline
          tblHeader cantSplit contextualSpacing highlight
          rPr pPr trPr tcPr
        ].freeze

        def fix_ooxml_format(xml)
          bool_elem_pattern = OOXML_BOOLEAN_ELEMENTS.join("|")

          xml = xml.gsub(
            /<([a-zA-Z][a-zA-Z0-9]*):(#{bool_elem_pattern})([^>]*)\/>/,
          ) do
            prefix = $1
            element_name = $2
            attrs = $3
            fixed_attrs = attrs.sub(/\s+w:val="(?:true|1)"/, "")
            fixed_attrs == attrs ? $& : "<#{prefix}:#{element_name}#{fixed_attrs}/>"
          end

          xml = xml.gsub(
            /<([a-zA-Z][a-zA-Z0-9]*):(#{bool_elem_pattern})([^>]*)><\/\1:\2>/,
          ) do
            prefix = $1
            element_name = $2
            attrs = $3
            fixed_attrs = attrs.sub(/\s+w:val="(?:true|1)"/, "")
            fixed_attrs == attrs ? $& : "<#{prefix}:#{element_name}#{fixed_attrs}/>"
          end

          xml = xml.gsub(
            /<([a-zA-Z][a-zA-Z0-9]*):(#{bool_elem_pattern})([^>]*)>(?:true|1)<\/\1:\2>/,
          ) do
            prefix = $1
            element_name = $2
            attrs = $3.sub(/\s+w:val="(?:true|1)"/, "")
            "<#{prefix}:#{element_name}#{attrs}/>"
          end

          xml = xml.gsub(
            /<([a-zA-Z][a-zA-Z0-9]*):(#{bool_elem_pattern})>(?:true|1)<\/\1:\2>/,
          ) { "<#{$1}:#{$2}/>" }

          xml.gsub(/\bw:xml:space=/, "xml:space=")
        end
      end
    end
  end
end
