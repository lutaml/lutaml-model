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
          when Moxml::Comment
            "comment"
          when Moxml::ProcessingInstruction
            "processing_instruction"
          when Moxml::Comment
            "comment"
          else
            element.name
          end
        end

        # Get the node type of an XML element
        #
        # This returns the actual node type based on the underlying library's
        # classification, not inferred from the element name.
        #
        # @param element [Moxml::Element, Moxml::Text, Moxml::Cdata, nil] The element
        # @return [Symbol, nil] The node type (:element, :text, :cdata, :comment, :processing_instruction)
        def node_type_of(element)
          return nil if element.nil?

          case element
          when Moxml::Text
            :text
          when Moxml::Cdata
            :cdata
          when Moxml::Comment
            :comment
          when Moxml::ProcessingInstruction
            :processing_instruction
          when Moxml::Comment
            :comment
          else
            :element
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
            Element.new("Text", "text", node_type: :text)
          else
            Element.new("Element", name_of(child), node_type: :element)
          end
        end

        # Get the prefix for a namespace URI from hoisted declarations
        #
        # This checks if a namespace URI is already declared in hoisted_declarations
        # and returns the prefix that should be used. This prevents duplicate xmlns
        # declarations when both hoisted_declarations and attribute code try to add
        # the same namespace.
        #
        # @param namespace_uri [String] The namespace URI to look up
        # @param hoisted_declarations [Hash{String, nil => String}] The hoisted declarations
        #   (keys are prefixes or nil for default, values are URIs)
        # @return [String, nil] The prefix if found, nil if not hoisted
        def prefix_for_namespace_uri(namespace_uri, hoisted_declarations)
          return nil unless hoisted_declarations

          hoisted_declarations.each do |prefix, uri|
            return prefix if uri == namespace_uri
          end
          nil
        end

        # Check if a namespace URI is already hoisted
        #
        # @param namespace_uri [String] The namespace URI to check
        # @param hoisted_declarations [Hash{String, nil => String}] The hoisted declarations
        # @return [Boolean] true if the namespace is already hoisted
        def namespace_uri_hoisted?(namespace_uri, hoisted_declarations)
          prefix_for_namespace_uri(namespace_uri, hoisted_declarations) != nil
        end
      end
    end
  end
end
