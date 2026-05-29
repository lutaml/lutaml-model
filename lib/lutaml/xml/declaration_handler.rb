module Lutaml
  module Xml
    # DeclarationHandler provides XML declaration extraction from input XML.
    #
    # Extraction methods detect and parse XML declarations from input strings.
    # Generation is handled by moxml's document model — no manual string assembly.
    module DeclarationHandler
      # Extract XML declaration information from input string
      #
      # Detects if input had an XML declaration and extracts version/encoding/standalone.
      # This is used for round-trip preservation of declarations.
      #
      # @param xml [String] the XML string to parse
      # @return [Hash] declaration info { version:, encoding:, standalone:, had_declaration: }
      def self.extract_xml_declaration(xml)
        # Use string operations instead of regex to avoid ReDoS vulnerability
        # This approach is O(n) with no backtracking

        # Strip leading whitespace
        trimmed = xml.lstrip

        # Fast prefix check - no regex needed
        return { had_declaration: false } unless trimmed.start_with?("<?xml")

        # Find the end of the declaration (?>)
        # Limit search to first 100 chars to avoid scanning entire document
        search_region = trimmed[0, 100]
        end_pos = search_region.index("?>", 5)
        return { had_declaration: false } unless end_pos

        # Extract content between <?xml and ?>
        decl_content = trimmed[5...end_pos]

        # Extract version (defaults to "1.0")
        version = extract_attribute(decl_content, "version") || "1.0"

        # Extract encoding (may be absent)
        encoding = extract_attribute(decl_content, "encoding")

        # Extract standalone (may be absent)
        standalone = extract_attribute(decl_content, "standalone")

        {
          version: version,
          encoding: encoding,
          standalone: standalone,
          had_declaration: true,
        }
      end

      # Extract an attribute value from declaration content
      # Uses simple string parsing to avoid regex ReDoS
      #
      # @param content [String] the declaration content (between <?xml and ?>)
      # @param attr_name [String] the attribute name to find
      # @return [String, nil] the attribute value or nil if not found
      def self.extract_attribute(content, attr_name)
        # Find attribute name followed by =
        name_start = content.index("#{attr_name}=")
        return nil unless name_start

        # Get the position after attr=
        pos = name_start + attr_name.length + 1

        # Skip any whitespace
        pos += 1 while pos < content.length && content[pos] == " "

        return nil if pos >= content.length

        # Check quote character
        quote = content[pos]
        return nil unless ['"', "'"].include?(quote)

        # Find closing quote
        end_quote = content.index(quote, pos + 1)
        return nil unless end_quote

        # Extract value between quotes
        content[(pos + 1)...end_quote]
      end

      # Determine if XML declaration should be included in output
      #
      # Supports multiple modes:
      # - false: omit declaration
      # - true: force include with defaults
      # - :preserve: include if input had one
      # - String: custom version string
      #
      # @param options [Hash] serialization options
      # @param xml_declaration [Hash] extracted declaration info from input
      # @return [Boolean] true if declaration should be included
      def should_include_declaration?(options, xml_declaration = nil)
        xml_declaration ||= @xml_declaration

        if options.key?(:declaration)
          case options[:declaration]
          when false
            false
          when true
            true
          when :preserve
            xml_declaration&.dig(:had_declaration) || false
          when String
            true
          else
            xml_declaration&.dig(:had_declaration) || false
          end
        else
          xml_declaration&.dig(:had_declaration) || false
        end
      end
    end
  end
end
