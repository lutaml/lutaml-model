module Lutaml
  module Xml
    # InputNamespaceExtractor provides namespace extraction functionality
    # for all XML adapter implementations.
    #
    # This module implements Issue #3: Namespace Preservation
    # by extracting all xmlns declarations from the root element
    # for round-trip preservation during serialization.
    module InputNamespaceExtractor
      # Extract all xmlns namespace declarations from root element
      #
      # This captures ALL xmlns declarations from the input XML
      # regardless of whether they're used in the document.
      # These declarations are preserved during serialization (Tier 1 priority).
      #
      # @param root_element [Object] the root element (adapter-specific type)
      # @param adapter_type [Symbol] the adapter type (:nokogiri, :oga, or :ox)
      # @return [Hash] map of prefix/uri pairs from input
      #   Keys are prefix symbols (:default for default namespace, or prefix name)
      #   Values are hashes with :uri, :prefix, and :format keys
      #     :format is either :default (xmlns="uri") or :prefix (xmlns:pfx="uri")
      def self.extract(root_element, adapter_type)
        return {} unless root_element

        case adapter_type
        when :nokogiri
          extract_nokogiri(root_element)
        when :oga
          extract_oga(root_element)
        when :ox
          extract_ox(root_element)
        else
          {}
        end
      end

      # Extract xmlns declarations directly from raw XML string.
      #
      # This method parses the raw XML string to extract xmlns declarations
      # BEFORE any XML parsing occurs. This is critical for preserving the
      # original namespace URIs when XML has been pre-normalized (e.g., alias
      # URIs converted to canonical URIs before lutaml's parse).
      #
      # Unlike #extract which works on parsed elements (and thus only sees
      # what Nokogiri observed after parsing), this method captures what was
      # actually in the input string.
      #
      # @param raw_xml [String] the raw XML string before parsing
      # @return [Hash] map of prefix/uri pairs with format information
      #   Keys are prefix symbols (:default for default namespace, or prefix name)
      #   Values are hashes with :uri, :prefix, and :format keys
      def self.extract_from_raw_xml(raw_xml)
        namespaces = {}

        # Only process actual XML (check for XML declaration or root element)
        return namespaces unless raw_xml.is_a?(String) &&
          raw_xml.strip.start_with?("<", "<?")

        # Match xmlns="uri" and xmlns:prefix="uri" patterns
        # This regex captures:
        # - xmlns="uri" (default namespace, prefix will be nil)
        # - xmlns:prefix="uri" (prefixed namespace)
        raw_xml.scan(/xmlns(?::([a-zA-Z0-9_-]+))="([^"]+)"/) do |prefix, uri|
          key = if prefix.nil? || prefix.empty?
                  :default
                else
                  prefix.to_sym
                end
          namespaces[key] = {
            uri: uri,
            prefix: prefix,
            format: prefix && !prefix.empty? ? :prefix : :default,
          }
        end

        namespaces
      end

      # Extract namespaces from Nokogiri root element
      #
      # @param root_element [Nokogiri::XML::Element] the root element
      # @return [Hash] map of prefix/uri pairs with format information
      def self.extract_nokogiri(root_element)
        namespaces = {}

        # Nokogiri's namespace_definitions returns all xmlns declarations
        # on this element (not inherited from ancestors)
        root_element.namespace_definitions.each do |ns_def|
          prefix_key = ns_def.prefix || :default
          namespaces[prefix_key] = {
            uri: ns_def.href,
            prefix: ns_def.prefix, # nil for default namespace
            format: ns_def.prefix ? :prefix : :default,
          }
        end

        namespaces
      end

      # Extract namespaces from Oga/Moxml root element
      #
      # @param root_element [Moxml::Element] the root element
      # @return [Hash] map of prefix/uri pairs with format information
      def self.extract_oga(root_element)
        namespaces = {}

        # Moxml exposes namespace declarations via the namespaces collection,
        # NOT as regular attributes. Use namespaces method to get all declarations.
        if root_element.respond_to?(:namespaces)
          root_element.namespaces.each do |ns|
            prefix = ns.prefix
            if prefix.nil? || prefix.empty?
              # Default namespace (xmlns="uri")
              namespaces[:default] = {
                uri: ns.uri,
                prefix: nil,
                format: :default,
              }
            else
              # Prefixed namespace (xmlns:prefix="uri")
              namespaces[prefix.to_sym] = {
                uri: ns.uri,
                prefix: prefix,
                format: :prefix,
              }
            end
          end
        end

        namespaces
      end

      # Extract namespaces from Ox root element
      #
      # @param root_element [Ox::Element] the root element
      # @return [Hash] map of prefix/uri pairs with format information
      def self.extract_ox(root_element)
        namespaces = {}

        # Ox elements have namespaces as attributes
        return namespaces unless root_element.respond_to?(:attributes)

        root_element.attributes.each do |name, value|
          name_str = name.to_s
          if name_str == "xmlns"
            # Default namespace
            namespaces[:default] = {
              uri: value,
              prefix: nil,
              format: :default,
            }
          elsif name_str.start_with?("xmlns:")
            # Prefixed namespace
            prefix = name_str.sub("xmlns:", "")
            namespaces[prefix.to_sym] = {
              uri: value,
              prefix: prefix,
              format: :prefix,
            }
          end
        end

        namespaces
      end
    end
  end
end
