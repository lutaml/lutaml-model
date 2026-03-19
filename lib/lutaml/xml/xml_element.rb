# frozen_string_literal: true

module Lutaml
  module Xml
    class XmlElement
      XML_NAMESPACE_URI = "http://www.w3.org/XML/1998/namespace"

      # Performance: Frozen string constants for frequently used values
      TEXT_NODE_NAME = "text"
      CDATA_NODE_NAME = "#cdata-section"
      XMLNS_PREFIX = "xmlns"

      # Performance: Frozen empty hash to reduce allocations
      EMPTY_NAMESPACES = {}.freeze

      # Node types for XML elements
      # - :element - regular XML element
      # - :text - text content node
      # - :cdata - CDATA section
      # - :comment - XML comment
      # - :processing_instruction - processing instruction
      NODE_TYPES = %i[element text cdata comment processing_instruction].freeze

      attr_reader :attributes,
                  :children,
                  :namespace_prefix,
                  :parent_document,
                  :node_type

      attr_accessor :adapter_node

      # Cache for order method - invalidated when children change
      attr_writer :order_cache

      # Detect if xmlns="" is explicitly set (W3C explicit no namespace)
      # This is a helper method for adapters to use during element initialization
      #
      # @param has_empty_xmlns [Boolean] true if xmlns="" is present
      # @param node_namespace_nil [Boolean] true if the node has no namespace
      # @return [Boolean] true if both conditions met (explicit no namespace)
      def self.detect_explicit_no_namespace(has_empty_xmlns:,
  node_namespace_nil:)
        has_empty_xmlns && node_namespace_nil
      end

      def initialize(
        node,
      attributes = {},
      children = [],
      text = nil,
      name: nil,
      parent_document: nil,
      namespace_prefix: nil,
      default_namespace: nil,
      explicit_no_namespace: false,
      node_type: nil
      )
        @name = name
        @namespace_prefix = namespace_prefix
        @attributes = attributes
        @children = children
        @text = text
        @parent_document = parent_document
        @default_namespace = default_namespace
        @explicit_no_namespace = explicit_no_namespace
        # Set node_type, defaulting to :element
        # Backward compatibility: infer from name if node_type not provided
        @node_type = node_type || infer_node_type_from_name(name)

        self.adapter_node = node
      end

      # This tells which attributes to pretty print, So we remove the
      # @parent_document and @adapter_node because they were causing
      # so much repeatative output.
      def pretty_print_instance_variables
        (instance_variables - %i[@adapter_node @parent_document]).sort
      end

      # Check if this is a text content node
      # Uses explicit node_type instead of name-based detection
      def text?
        @node_type == :text
      end

      # Check if this is a CDATA section
      def cdata?
        @node_type == :cdata
      end

      # Check if this is a comment node
      def comment?
        @node_type == :comment
      end

      # Check if this is a regular element (not text/cdata/comment)
      def element?
        @node_type == :element
      end

      # Check if this is a processing instruction
      def processing_instruction?
        @node_type == :processing_instruction
      end

      # Backward compatibility: infer node_type from name
      # This allows old code that doesn't pass node_type to still work
      private def infer_node_type_from_name(name)
        case name
        when "text" then :text
        when "#cdata-section" then :cdata
        when "comment" then :comment
        when "processing_instruction" then :processing_instruction
        else :element
        end
      end

      def name
        return @name unless namespace_prefix

        "#{namespace_prefix}:#{@name}"
      end

      def namespaced_name
        return @name if text?
        # If xmlns="" was explicitly set, element has NO namespace
        return @name if @explicit_no_namespace

        # Priority order for namespace resolution:
        # 1. If has explicit prefix, use namespaces[prefix]
        # 2. If has @default_namespace, use it (preferred for default ns)
        # 3. Fall back to namespaces[nil] if exists
        # 4. Return unprefixed name

        if namespace_prefix && namespaces[namespace_prefix]
          "#{namespaces[namespace_prefix].uri}:#{@name}"
        elsif @default_namespace
          "#{@default_namespace}:#{@name}"
        elsif namespaces[nil]
          "#{namespaces[nil].uri}:#{@name}"
        else
          @name
        end
      end

      def unprefixed_name
        @name
      end

      def document
        Document.new(self)
      end

      def namespaces
        # Performance: Return frozen empty hash instead of creating new one
        @namespaces || @parent_document&.namespaces || EMPTY_NAMESPACES
      end

      def own_namespaces
        # Performance: Return frozen empty hash instead of creating new one
        @namespaces || EMPTY_NAMESPACES
      end

      def namespace
        return @namespace if defined?(@namespace)

        @namespace = if namespace_prefix
                       namespaces[namespace_prefix]
                     else
                       default_namespace
                     end
      end

      def attribute_is_namespace?(name)
        name.to_s.start_with?(XMLNS_PREFIX)
      end

      def add_namespace(namespace)
        @namespaces ||= {}
        @namespaces[namespace.prefix] = namespace
      end

      def default_namespace
        namespaces[nil] || @parent_document&.namespaces&.dig(nil)
      end

      def order
        return @order_cache if @order_cache

        @order_cache = children.map do |child|
          if child.text?
            # For text nodes:
            # - name is "text" for backward compatibility with tests
            # - text_content contains the actual text for round-trip serialization
            # - node_type explicitly marks this as a text node
            Lutaml::Xml::Element.new("Text", "text",
                                     text_content: child.text,
                                     node_type: :text)
          elsif child.cdata?
            # For CDATA sections:
            # - name is "#cdata-section" for backward compatibility
            # - text_content contains the actual CDATA content
            # - node_type explicitly marks this as CDATA
            Lutaml::Xml::Element.new("Text", "#cdata-section",
                                     text_content: child.text,
                                     node_type: :cdata)
          else
            # For regular elements:
            # - name is the actual element name
            # - node_type explicitly marks this as an element
            Lutaml::Xml::Element.new("Element", child.unprefixed_name,
                                     node_type: :element)
          end
        end
      end

      def root
        self
      end

      def text
        return @text if children.empty?
        return text_children.map(&:text) if children.count > 1

        text_children.map(&:text).join
      end

      def cdata
        return @text if children.empty?
        return cdata_children.map(&:text) if children.count > 1

        cdata_children.map(&:text).join
      end

      def cdata_children
        children.select(&:cdata?)
      end

      def text_children
        children.select { |child| child.text? && !child.cdata? }
      end

      def [](name)
        find_attribute_value(name) || find_children_by_name(name)
      end

      def find_attribute_value(attribute_name)
        if attribute_name.is_a?(Array)
          attributes.values.find do |attr|
            attribute_name.include?(attr.namespaced_name)
          end&.value
        else
          attributes.values.find do |attr|
            attribute_name == attr.namespaced_name
          end&.value
        end
      end

      def find_children_by_name(name)
        if name.is_a?(Array)
          children.select { |child| name.include?(child.namespaced_name) }
        else
          children.select { |child| child.namespaced_name == name }
        end
      end

      def find_child_by_name(name)
        find_children_by_name(name).first
      end

      def to_h
        document.to_h
      end

      def nil_element?
        find_attribute_value("xsi:nil") == "true"
      end
    end
  end
end
