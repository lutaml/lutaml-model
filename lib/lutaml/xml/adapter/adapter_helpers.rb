# frozen_string_literal: true

module Lutaml
  module Xml
    module Adapter
      # Shared helper methods for XML adapters.
      #
      # This module provides common functionality used by both OgaAdapter
      # and RexmlAdapter to reduce code duplication.
      #
      # @example Including in an adapter
      #   class OgaAdapter < BaseAdapter
      #     extend AdapterHelpers
      #   end
      module AdapterHelpers
        # Text node classes that should be handled specially
        TEXT_CLASSES = [Moxml::Text, Moxml::Cdata].freeze

        # Get the name of an XML element
        #
        # @param element [Moxml::Element, Moxml::Text, Moxml::Cdata, nil] The element
        # @return [String, nil] The element name or nil
        def name_of(element)
          return nil if element.nil?

          case element
          when Moxml::Text
            "text"
          when Moxml::Cdata
            "#cdata-section"
          when Moxml::ProcessingInstruction
            "processing_instruction"
          else
            element.name
          end
        end

        # Get the prefixed name of an XML node
        #
        # @param node [Moxml::Node] The XML node
        # @return [String] The prefixed name (e.g., "prefix:name" or "name")
        def prefixed_name_of(node)
          return name_of(node) if TEXT_CLASSES.include?(node.class)

          [node&.namespace&.prefix, node.name].compact.join(":")
        end

        # Get the namespaced attribute name
        #
        # @param attribute [Moxml::Attribute] The attribute
        # @return [String] The namespaced attribute name
        def namespaced_attr_name(attribute)
          attr_ns = attribute.namespace
          attr_name = attribute.name
          return attr_name unless attr_ns

          # Special handling for xml:lang - use prefix instead of URI
          prefix = attr_name == "lang" ? attr_ns.prefix : attr_ns.uri
          [prefix, attr_name].compact.join(":")
        end

        # Get the namespaced name of an XML node
        #
        # @param node [Moxml::Node] The XML node
        # @return [String] The namespaced name (e.g., "uri:name" or "name")
        def namespaced_name_of(node)
          return name_of(node) unless node.respond_to?(:namespace)

          [node&.namespace&.uri, node.name].compact.join(":")
        end

        # Check if a node is a text node
        #
        # @param node [Object] The node to check
        # @return [Boolean] true if text or cdata node
        def text_node?(node)
          TEXT_CLASSES.include?(node.class)
        end

        # Build Element object from child node
        #
        # @param child [Moxml::Node] The child node
        # @return [Element] The Element object
        def build_element_from_child(child)
          if text_node?(child)
            Element.new("Text", "text")
          else
            Element.new("Element", name_of(child))
          end
        end
      end
    end
  end
end
