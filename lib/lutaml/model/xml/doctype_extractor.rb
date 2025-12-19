# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # Extracts DOCTYPE information from raw XML strings
      #
      # This module provides a shared method to extract DOCTYPE declarations
      # from raw XML strings when the XML library doesn't directly expose this
      # information (as is the case with Moxml/Oga and Ox).
      #
      # Nokogiri provides native access to DOCTYPE via `parsed.internal_subset`,
      # so it doesn't need this extraction method.
      #
      # This logic is identical in both Oga and Ox adapters and has been
      # extracted here to maintain DRY principles.
      module DocTypeExtractor
        # Extract DOCTYPE information from raw XML string
        #
        # Parses the DOCTYPE declaration using a regex pattern to extract:
        # - Document type name
        # - Public identifier (if PUBLIC doctype)
        # - System identifier (external DTD location)
        #
        # @param xml [String] the raw XML string
        # @return [Hash, nil] DOCTYPE info hash or nil if no DOCTYPE found
        #   - :name [String] the document type name
        #   - :public_id [String, nil] the public identifier (PUBLIC only)
        #   - :system_id [String, nil] the system identifier
        #
        # @example Parsing a PUBLIC DOCTYPE
        #   xml = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">'
        #   info = extract_doctype_from_xml(xml)
        #   # => {name: "html", public_id: "-//W3C//DTD XHTML 1.0//EN", system_id: "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"}
        #
        # @example Parsing a SYSTEM DOCTYPE
        #   xml = '<!DOCTYPE note SYSTEM "note.dtd">'
        #   info = extract_doctype_from_xml(xml)
        #   # => {name: "note", public_id: nil, system_id: "note.dtd"}
        def extract_doctype_from_xml(xml)
          # Match DOCTYPE declaration using regex
          if xml =~ /<!DOCTYPE\s+(\S+)(?:\s+(PUBLIC|SYSTEM)\s+"([^"]+)"(?:\s+"([^"]+)")?)?\s*>/
            {
              name: $1,
              public_id: ($2 == "PUBLIC" ? $3 : nil),
              system_id: ($2 == "PUBLIC" ? $4 : $3),
            }
          end
        end
      end
    end
  end
end