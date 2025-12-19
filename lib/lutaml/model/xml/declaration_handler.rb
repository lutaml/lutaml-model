module Lutaml
  module Model
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
          # Match XML declaration at start of document
          # Format: <?xml version="1.0" encoding="UTF-8"?>
          # Both version and encoding are optional in the match
          # Use character class excluding '>' to prevent ReDoS
          if xml.match(/\A[ \t\r\n]*<\?xml[ \t\r\n]+([^>]+)\?>/)
            decl_content = ::Regexp.last_match(1)

            # Extract version (defaults to "1.0")
            version = if decl_content.match(/version\s*=\s*["']([^"']+)["']/)
                        ::Regexp.last_match(1)
                      else
                        "1.0"
                      end

            # Extract encoding (may be absent)
            encoding = if decl_content.match(/encoding\s*=\s*["']([^"']+)["']/)
                         ::Regexp.last_match(1)
                       end

            {
              version: version,
              encoding: encoding,
              had_declaration: true,
            }
          else
            # No XML declaration found
            {
              had_declaration: false
            }
          end
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
            parts << %Q(PUBLIC "#{doctype[:public_id]}")
            parts << %Q("#{doctype[:system_id]}") if doctype[:system_id]
          elsif doctype[:system_id]
            parts << %Q(SYSTEM "#{doctype[:system_id]}")
          end

          parts.join(" ") + ">\n"
        end
      end
    end
  end
end