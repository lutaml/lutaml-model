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

      # Performance: Frozen empty array for child lookups
      EMPTY_CHILDREN_ARRAY = [].freeze

      # Node types for XML elements
      # - :element - regular XML element
      # - :text - text content node
      # - :cdata - CDATA section
      # - :comment - XML comment
      # - :processing_instruction - processing instruction
      NODE_TYPES = %i[element text cdata comment processing_instruction].freeze

      attr_reader :children, :attributes, :namespace_prefix,
                  :namespace_prefix_explicit, :parent_document, :node_type
      attr_accessor :adapter_node

      # Cache for order method - invalidated when children change
      attr_writer :order_cache

      # Performance: Invalidate child index when children are set

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

      # Convert a Formal Public Identifier (FPI) to a URN per RFC 3151.
      # FPI examples: "-//OASIS//DTD XML Exchange Table Model 19990315//EN"
      # Returns nil if the string is not an FPI.
      #
      # RFC 3151 format: urn:publicid:prefix:+/-//registrant//description//language//
      # Conversion: replace spaces with +, prepend "urn:publicid:"
      def self.fpi_to_urn(fpi)
        return nil unless fpi.is_a?(String) && fpi.start_with?("-//", "+//")

        # Replace spaces with + per RFC 3151
        "urn:publicid:#{fpi.gsub(' ', '+')}"
      end

      # Detect if a string is an FPI (Formal Public Identifier), not a valid namespace URI.
      # FPIs start with -// or +// (SGML-style, not a URI scheme).
      def self.fpi?(uri)
        uri.is_a?(String) && uri.start_with?("-//", "+//")
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
        @namespace_prefix_explicit = !namespace_prefix.nil? && !namespace_prefix.empty?
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

      # Performance: Override children= to invalidate caches
      def children=(new_children)
        @children = new_children
        @children_index = nil
        @order_cache = nil
      end

      # This tells which attributes to pretty print, So we remove the
      # @parent_document and @adapter_node because they were causing
      # so much repeatative output.
      def pretty_print_instance_variables
        (instance_variables - %i[@adapter_node @parent_document
                                 @children_index]).sort
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
        # When @namespaces is non-empty, return it directly (element has own declarations)
        # When @namespaces is nil or empty, fall back to parent's in-scope namespaces
        # This supports the new namespace_definitions approach where each element only
        # stores its own declarations, and child elements inherit from parent
        if @namespaces&.any?
          @namespaces
        else
          @parent_document&.namespaces || EMPTY_NAMESPACES
        end
      end

      def own_namespaces
        # Return only this element's own namespace declarations (not inherited)
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

      # Get the namespace URI of this element.
      #
      # Returns the URI string for namespace-aware type resolution.
      # Returns nil if the element has no namespace.
      #
      # @return [String, nil] The namespace URI or nil
      def namespace_uri
        ns = namespace
        ns&.uri
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

        @order_cache = children.filter_map do |child|
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
          elsif child.comment?
            # Skip comments - they're not part of schema element order
            nil
          else
            # For regular elements:
            # - name is the actual element name
            # - node_type explicitly marks this as an element
            # - namespace_uri and namespace_prefix preserve namespace info for rule matching
            Lutaml::Xml::Element.new("Element", child.unprefixed_name,
                                     node_type: :element,
                                     namespace_uri: child.namespace_uri,
                                     namespace_prefix: child.namespace_prefix)
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

      # Performance: Build index for O(1) child lookups by name
      # Called once per element, then reused for all lookups
      def ensure_children_index
        return if @children_index

        @children_index = {}
        @children.each do |child|
          key = child.namespaced_name
          @children_index[key] ||= []
          @children_index[key] << child
        end
      end

      # Find children by namespaced name using indexed lookup
      # Performance: O(1) for single name, O(k) for k names
      def find_children_by_name(name)
        ensure_children_index

        if name.is_a?(Array)
          # Multiple names: collect from index
          name.flat_map { |n| @children_index[n] || EMPTY_CHILDREN_ARRAY }
        else
          @children_index[name] || EMPTY_CHILDREN_ARRAY
        end
      end

      def find_child_by_name(name)
        ensure_children_index

        if name.is_a?(Array)
          name.each do |n|
            found = @children_index[n]&.first
            return found if found
          end
          nil
        else
          @children_index[name]&.first
        end
      end

      def to_h
        document.to_h
      end

      def nil_element?
        find_attribute_value("xsi:nil") == "true"
      end

      private

      # Backward compatibility: infer node_type from name
      # This allows old code that doesn't pass node_type to still work
      def infer_node_type_from_name(name)
        case name
        when "text" then :text
        when "#cdata-section" then :cdata
        when "comment" then :comment
        when "processing_instruction" then :processing_instruction
        else :element
        end
      end
    end
  end
end
