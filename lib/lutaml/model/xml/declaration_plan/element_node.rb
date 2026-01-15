# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      class DeclarationPlan
        # ElementNode represents namespace decisions for a single XML element in the tree
        #
        # This is a PURE DATA structure - it stores decisions made by DeclarationPlanner
        # but contains NO decision-making logic itself.
        #
        # The ElementNode tree is isomorphic to the XmlDataModel tree, allowing adapters
        # to traverse both trees in parallel by index/position.
        #
        # @example
        #   element_node = ElementNode.new(
        #     qualified_name: "prefix:ElementName",
        #     use_prefix: "prefix",
        #     hoisted_declarations: { "xmlns:prefix" => "http://example.com/ns" }
        #   )
        #   element_node.add_attribute_node(attr_node)
        #   element_node.add_element_node(child_node)
        #
        class ElementNode
          # @return [String] Element name with prefix (e.g., "prefix:element" or "element")
          attr_reader :qualified_name

          # @return [String, nil] Prefix to use for this element (nil for default format)
          attr_reader :use_prefix

          # @return [Hash<String, String>] xmlns declarations to emit at this element
          #   Keys: "xmlns" or "xmlns:prefix"
          #   Values: namespace URIs
          attr_reader :hoisted_declarations

          # @return [Array<AttributeNode>] Attribute decisions (matched by index to XmlDataModel)
          attr_reader :attribute_nodes

          # @return [Array<ElementNode>] Child element decisions (matched by index to XmlDataModel)
          attr_reader :element_nodes

          # @return [Boolean] Whether this element needs xmlns="" declaration (W3C compliance)
          #   True when element is in blank namespace AND parent uses default format
          attr_reader :needs_xmlns_blank

          # Initialize an element node
          #
          # @param qualified_name [String] Element name with prefix
          # @param use_prefix [String, nil] Prefix for this element
          # @param hoisted_declarations [Hash<String, String>] xmlns attributes to declare here
          # @param needs_xmlns_blank [Boolean] Whether to add xmlns="" (W3C compliance)
          def initialize(qualified_name:, use_prefix:, hoisted_declarations: {}, needs_xmlns_blank: false)
            @qualified_name = qualified_name
            @use_prefix = use_prefix
            @hoisted_declarations = hoisted_declarations
            @attribute_nodes = []
            @element_nodes = []
            @needs_xmlns_blank = needs_xmlns_blank
          end

          # Add an attribute decision node
          #
          # @param node [AttributeNode] The attribute node to add
          # @return [AttributeNode] The added node
          def add_attribute_node(node)
            @attribute_nodes << node
            node
          end

          # Add a child element decision node
          #
          # @param node [ElementNode] The child element node to add
          # @return [ElementNode] The added node
          def add_element_node(node)
            @element_nodes << node
            node
          end

          # Check if this element uses default namespace format
          #
          # @return [Boolean] true if no prefix (default format)
          def uses_default_format?
            use_prefix.nil?
          end

          # Check if this element uses prefix format
          #
          # @return [Boolean] true if prefix present
          def uses_prefix_format?
            !use_prefix.nil?
          end
        end
      end
    end
  end
end