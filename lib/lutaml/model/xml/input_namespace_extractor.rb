module Lutaml
  module Model
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
        #   Values are hashes with :uri and :prefix keys
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

        private

        # Extract namespaces from Nokogiri root element
        #
        # @param root_element [Nokogiri::XML::Element] the root element
        # @return [Hash] map of prefix/uri pairs
        def self.extract_nokogiri(root_element)
          namespaces = {}

          # Nokogiri's namespace_definitions returns all xmlns declarations
          # on this element (not inherited from ancestors)
          root_element.namespace_definitions.each do |ns_def|
            prefix_key = ns_def.prefix || :default
            namespaces[prefix_key] = {
              uri: ns_def.href,
              prefix: ns_def.prefix, # nil for default namespace
            }
          end

          namespaces
        end

        # Extract namespaces from Oga/Moxml root element
        #
        # @param root_element [Moxml::Element] the root element
        # @return [Hash] map of prefix/uri pairs
        def self.extract_oga(root_element)
          namespaces = {}

          # Moxml elements have namespaces as attributes
          # Extract xmlns and xmlns:prefix attributes
          return namespaces unless root_element.respond_to?(:attributes)

          root_element.attributes.each do |attr|
            if attr.name == "xmlns"
              # Default namespace
              namespaces[:default] = {
                uri: attr.value,
                prefix: nil,
              }
            elsif attr.name.start_with?("xmlns:")
              # Prefixed namespace
              prefix = attr.name.sub("xmlns:", "")
              namespaces[prefix.to_sym] = {
                uri: attr.value,
                prefix: prefix,
              }
            end
          end

          namespaces
        end

        # Extract namespaces from Ox root element
        #
        # @param root_element [Ox::Element] the root element
        # @return [Hash] map of prefix/uri pairs
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
              }
            elsif name_str.start_with?("xmlns:")
              # Prefixed namespace
              prefix = name_str.sub("xmlns:", "")
              namespaces[prefix.to_sym] = {
                uri: value,
                prefix: prefix,
              }
            end
          end

          namespaces
        end
      end
    end
  end
end