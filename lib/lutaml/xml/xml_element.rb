# frozen_string_literal: true

module Lutaml
  module Xml
    class XmlElement
      XML_NAMESPACE_URI = "http://www.w3.org/XML/1998/namespace"

      # Performance: Frozen string constants for frequently used values
      TEXT_NODE_NAME = "text".freeze
      CDATA_NODE_NAME = "#cdata-section".freeze
      XMLNS_PREFIX = "xmlns".freeze

      # Performance: Frozen empty hash to reduce allocations
      EMPTY_NAMESPACES = {}.freeze

      attr_reader :attributes,
                  :children,
                  :namespace_prefix,
                  :parent_document

      attr_accessor :adapter_node

      # Cache for order method - invalidated when children change
      attr_writer :order_cache

      # Performance: Invalidate child index when children are set
      attr_writer :children

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
      explicit_no_namespace: false
      )
        @name = name
        @namespace_prefix = namespace_prefix
        @attributes = attributes
        @children = children
        @text = text
        @parent_document = parent_document
        @default_namespace = default_namespace
        @explicit_no_namespace = explicit_no_namespace
        @children_index = nil
        @children_count = nil

        self.adapter_node = node
      end

      # Performance: Override children= to invalidate caches
      def children=(new_children)
        @children = new_children
        @children_index = nil
        @children_count = nil
        @order_cache = nil
      end

      # This tells which attributes to pretty print, So we remove the
      # @parent_document and @adapter_node because they were causing
      # so much repeatative output.
      def pretty_print_instance_variables
        (instance_variables - %i[@adapter_node @parent_document]).sort
      end

      def text?
        @name == TEXT_NODE_NAME
      end

      def name
        return @cached_name if @cached_name

        @cached_name = if namespace_prefix
          "#{namespace_prefix}:#{@name}"
        else
          @name
        end
      end

      def namespaced_name
        return @namespaced_name if @namespaced_name
        return @namespaced_name = @name if text?
        # If xmlns="" was explicitly set, element has NO namespace
        return @namespaced_name = @name if @explicit_no_namespace

        # Priority order for namespace resolution:
        # 1. If has explicit prefix, use namespaces[prefix]
        # 2. If has @default_namespace, use it (preferred for default ns)
        # 3. Fall back to namespaces[nil] if exists
        # 4. Return unprefixed name

        @namespaced_name = if namespace_prefix && namespaces[namespace_prefix]
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
        return @cached_namespace if defined?(@cached_namespace)

        @cached_namespace = if namespace_prefix
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
            Lutaml::Xml::Element.new("Text", "text",
                                     text_content: child.text)
          else
            Lutaml::Xml::Element.new("Element", child.unprefixed_name)
          end
        end
      end

      def root
        self
      end

      def text
        return @text if children_count.zero?
        return text_children.map(&:text) if children_count > 1

        text_children.map(&:text).join
      end

      def cdata
        return @text if children_count.zero?
        return cdata_children.map(&:text) if children_count > 1

        cdata_children.map(&:text).join
      end

      # Performance: Cache children count to avoid repeated calls
      def children_count
        @children_count ||= @children.count
      end

      def cdata_children
        find_children_by_name(CDATA_NODE_NAME)
      end

      def text_children
        find_children_by_name(TEXT_NODE_NAME)
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

      def find_children_by_name(name)
        ensure_children_index

        if name.is_a?(Array)
          # Multiple names: collect from index
          name.flat_map { |n| @children_index[n] || [] }
        else
          @children_index[name] || []
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
    end
  end
end
