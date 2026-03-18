module Lutaml
  module Xml
    # DeclarationHandler provides XML declaration and DOCTYPE handling
    # for all XML adapter implementations.
    #
    # This module implements Issue #1: XML Declaration Preservation
    # across Nokogiri, Oga, and Ox adapters.
    module DeclarationHandler
      # Extract XML declaration information from input string
      #
      # Detects if input had an XML declaration and extracts version/encoding.
      # This is used for round-trip preservation of declarations.
      #
      # @param xml [String] the XML string to parse
      # @return [Hash] declaration info { version:, encoding:, had_declaration: }
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

        {
          version: version,
          encoding: encoding,
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
        # Use instance variable if not provided (for adapter instance methods)
        xml_declaration ||= @xml_declaration

        if options.key?(:declaration)
          case options[:declaration]
          when false
            # Explicit false: omit declaration
            false
          when true
            # Explicit true: force include
            true
          when :preserve
            # Preserve mode: include if input had one
            xml_declaration&.dig(:had_declaration) || false
          when String
            # Custom version string: include
            true
          else
            # Default: preserve from input
            xml_declaration&.dig(:had_declaration) || false
          end
        else
          # No declaration option provided: default behavior is preserve from input
          xml_declaration&.dig(:had_declaration) || false
        end
      end

      # Generate XML declaration string
      #
      # Uses stored declaration info if available, otherwise uses defaults.
      # Supports custom version strings and encoding options.
      #
      # @param options [Hash] serialization options
      #   - :declaration => String for custom version, true for default
      #   - :encoding => String or true for UTF-8
      # @param xml_declaration [Hash] extracted declaration info from input
      # @return [String] the XML declaration (includes trailing newline)
      def generate_declaration(options, xml_declaration = nil)
        # Use instance variable if not provided (for adapter instance methods)
        xml_declaration ||= @xml_declaration

        # Determine version
        # When declaration: true (force), use default 1.0 not input version
        # When declaration: "1.x" (custom), use that string
        # When preserving (no option or :preserve), use input version or default
        version = if options[:declaration].is_a?(String)
                    # Custom version string
                    options[:declaration]
                  elsif options[:declaration] == true
                    # Force with default version
                    "1.0"
                  elsif xml_declaration&.dig(:version)
                    # Preserve from input
                    xml_declaration[:version]
                  else
                    # Default fallback
                    "1.0"
                  end

        # Determine encoding
        # Priority: explicit encoding option > input encoding > none
        encoding = if options[:encoding].is_a?(String)
                     options[:encoding]
                   elsif options[:encoding] == true
                     "UTF-8"
                   elsif xml_declaration&.dig(:encoding)
                     xml_declaration[:encoding]
                   end

        declaration = "<?xml version=\"#{version}\""
        declaration += " encoding=\"#{encoding}\"" if encoding
        declaration += "?>\n"
        declaration
      end

      # Generate DOCTYPE declaration from doctype hash
      #
      # Supports both PUBLIC and SYSTEM DTDs.
      # Format: <!DOCTYPE name PUBLIC "public_id" "system_id">
      #         <!DOCTYPE name SYSTEM "system_id">
      #
      # @param doctype [Hash] the doctype information
      #   - :name => root element name
      #   - :public_id => public identifier (optional)
      #   - :system_id => system identifier (optional)
      # @return [String, nil] the DOCTYPE declaration or nil if no doctype
      def generate_doctype_declaration(doctype)
        return nil unless doctype

        parts = ["<!DOCTYPE #{doctype[:name]}"]

        if doctype[:public_id]
          parts << %(PUBLIC "#{doctype[:public_id]}")
          parts << %("#{doctype[:system_id]}") if doctype[:system_id]
        elsif doctype[:system_id]
          parts << %(SYSTEM "#{doctype[:system_id]}")
        end

        "#{parts.join(' ')}>\n"
      end
    end
  end
end
