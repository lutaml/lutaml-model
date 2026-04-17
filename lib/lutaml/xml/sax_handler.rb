# frozen_string_literal: true

require "moxml"

module Lutaml
  module Xml
    # SAX handler that builds XmlElement trees from Moxml SAX events.
    #
    # This provides a fast, memory-efficient alternative to DOM parsing for
    # read-only (deserialization) workloads. Instead of building a full DOM
    # tree and then converting to XmlElement, SAX events directly construct
    # XmlElement instances, eliminating one intermediate tree.
    #
    # Usage:
    #   context = Moxml.new(:nokogiri)
    #   handler = SaxHandler.new
    #   context.sax_parse(xml, handler)
    #   root = handler.root  # => XmlElement
    #
    class SaxHandler < Moxml::SAX::ElementHandler
      attr_reader :root

      def initialize
        super
        @element_stack = []
        @ns_scope_stack = [{}] # Stack of in-scope namespace prefix → URI maps
        @text_buffer = nil
        @root = nil
        @default_namespace = nil
      end

      def on_start_element(name, attributes = {}, namespaces = {})
        flush_text!

        prefix, local_name = split_name(name)
        parent = @element_stack.last

        # Update in-scope namespace map: inherit from parent, overlay new declarations
        current_scope = @ns_scope_stack.last.dup
        namespaces.each do |ns_prefix, ns_uri|
          current_scope[ns_prefix] = ns_uri
        end
        @ns_scope_stack << current_scope

        # Track default namespace from root element
        if @element_stack.empty? && namespaces[nil]
          @default_namespace = namespaces[nil]
        end

        # Build XmlAttribute model objects from raw SAX attributes
        # Uses current_scope (inherited + local) for namespace resolution
        attrs = build_attributes(attributes, current_scope)

        # Determine effective namespace prefix for this element
        effective_prefix = prefix unless prefix.nil? || prefix.empty?
        effective_prefix = nil if effective_prefix == ""

        # Detect explicit no-namespace (xmlns="")
        explicit_no_namespace = namespaces.key?(nil) && namespaces[nil] == "" && effective_prefix.nil?

        element = XmlElement.new(
          nil,
          attrs,
          [],
          nil,
          name: local_name,
          namespace_prefix: effective_prefix,
          parent_document: parent,
          default_namespace: @default_namespace,
          explicit_no_namespace: explicit_no_namespace,
          node_type: :element,
        )

        # Store namespace declarations on the element
        namespaces.each do |ns_prefix, ns_uri|
          ns = Adapter::NamespaceData.new(ns_uri, ns_prefix)
          element.add_namespace(ns)
        end

        if parent
          parent.children << element
        else
          @root = element
        end

        @element_stack << element
      end

      def on_characters(text)
        return if @element_stack.empty?

        @text_buffer ||= +""
        @text_buffer << text
      end

      def on_cdata(text)
        return if @element_stack.empty?

        flush_text!
        element = @element_stack.last

        cdata_node = XmlElement.new(
          nil,
          {},
          [],
          text,
          name: "text",
          parent_document: element,
          node_type: :cdata,
        )
        element.children << cdata_node
      end

      def on_end_element(_name)
        flush_text!
        @element_stack.pop
        @ns_scope_stack.pop
      end

      private

      # Build XmlAttribute instances from raw SAX attribute data.
      # Resolves namespace URI from the attribute's prefix using in-scope namespaces.
      def build_attributes(attributes, scope)
        attributes.each_with_object({}) do |(attr_name, attr_value), hash|
          namespace_prefix = if attr_name.include?(":")
                               attr_name.split(":", 2).first
                             end
          namespace = namespace_prefix ? scope[namespace_prefix] : nil
          hash[attr_name] = XmlAttribute.new(
            attr_name, attr_value,
            namespace: namespace,
            namespace_prefix: namespace_prefix
          )
        end
      end

      # Split qualified name into prefix and local name
      def split_name(name)
        if name.include?(":")
          prefix, local = name.split(":", 2)
          [prefix, local]
        else
          [nil, name]
        end
      end

      # Flush accumulated text into the current element
      def flush_text!
        return unless @text_buffer
        return if @element_stack.empty?

        text = @text_buffer
        @text_buffer = nil

        # Skip whitespace-only text (formatting between elements).
        # DOM parsers filter these out via Moxml; SAX must match.
        return if text.strip.empty?

        @text_buffer = nil

        element = @element_stack.last

        text_node = XmlElement.new(
          nil,
          {},
          [],
          text,
          name: "text",
          parent_document: element,
          node_type: :text,
        )
        element.children << text_node
      end
    end
  end
end
