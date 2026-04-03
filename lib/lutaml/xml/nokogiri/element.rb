# frozen_string_literal: true

module Lutaml
  module Xml
    class NokogiriElement < XmlElement
      include Nokogiri::EntityResolver

      # Performance: Frozen empty collections to reduce allocations
      EMPTY_NAMESPACES = {}.freeze
      EMPTY_ATTRIBUTES = {}.freeze

      # Use NamespaceData for adapter-internal namespace data
      NamespaceData = Lutaml::Xml::Adapter::NamespaceData
      EMPTY_CHILDREN = [].freeze

      def initialize(node, root_node: nil, default_namespace: nil,
                     parent_document: nil)
        # Defensive check: ensure node is not nil
        if node.nil?
          raise ArgumentError,
                "Cannot create NokogiriElement from nil node. " \
                "This usually means the XML document has no root element."
        end

        # Determine node type from Nokogiri's classification
        # This is the authoritative source - not inferred from name
        # IMPORTANT: Check CDATA before Text because CDATA inherits from Text
        node_type = case node
                    when ::Nokogiri::XML::CDATA then :cdata
                    when ::Nokogiri::XML::Text then :text
                    when ::Nokogiri::XML::Comment then :comment
                    else :element
                    end

        # Collect namespaces declared on THIS element only
        # namespace_definitions returns only xmlns declarations on this element,
        # unlike namespaces which returns all in-scope namespaces (including inherited)
        #
        # CRITICAL FIX: Previously, child elements added their namespaces to root_node,
        # causing sibling elements to incorrectly inherit each other's namespaces.
        # Now each element stores only its own declarations.
        node.namespace_definitions.each do |ns_def|
          namespace = NamespaceData.new(ns_def.href, ns_def.prefix)
          add_namespace(namespace)
        end

        # Performance: Use frozen empty hash when no attributes, otherwise build hash
        attributes = build_attributes_hash(node)

        # Detect if xmlns="" is explicitly set (explicit no namespace)
        # Use shared helper method for consistency across all adapters
        explicit_no_namespace = XmlElement.detect_explicit_no_namespace(
          has_empty_xmlns: node.namespaces.key?("xmlns") && node.namespaces["xmlns"] == "",
          node_namespace_nil: node.namespace.nil?,
        )

        # Use parent_document if explicitly provided (for child elements),
        # otherwise fall back to root_node (for root element)
        effective_parent = parent_document || root_node

        # Set default namespace for root, or inherit from parent for children
        if !node.namespace&.prefix
          default_namespace = node.namespace&.href ||
            effective_parent&.instance_variable_get(:@default_namespace)
        end

        super(
          node,
          attributes,
          parse_all_children(node, root_node: root_node || self,
                                   default_namespace: default_namespace),
          EncodingNormalizer.normalize_to_utf8(node.text),
          name: node.name,
          parent_document: effective_parent,
          namespace_prefix: node.namespace&.prefix,
          default_namespace: default_namespace,
          explicit_no_namespace: explicit_no_namespace,
          node_type: node_type
        )
      end

      # Override text? for Nokogiri-specific node type detection
      # Only actual text/cdata nodes return true, NOT elements named "text"
      # This fixes SVG <text> elements being incorrectly treated as text nodes
      def text?
        @node_type == :text || @node_type == :cdata
      end

      # Override text to handle EntityReference specially.
      # EntityReference.text returns "", but we need the entity syntax
      # (e.g., "&nbsp;") for proper text aggregation.
      def text
        if @adapter_node.is_a?(::Nokogiri::XML::EntityReference)
          return "&#{@adapter_node.name};"
        end

        return @text if children.empty?

        # Handle multiple children case specially to include EntityReference content
        if children.count > 1
          return children.map do |child|
            if child.is_a?(Lutaml::Xml::NokogiriElement) &&
               child.adapter_node.is_a?(::Nokogiri::XML::EntityReference)
              "&#{child.adapter_node.name};"
            else
              child.text
            end
          end.join
        end

        # Single child - check if it's an EntityReference
        child = children.first
        if child.is_a?(Lutaml::Xml::NokogiriElement) &&
           child.adapter_node.is_a?(::Nokogiri::XML::EntityReference)
          return "&#{child.adapter_node.name};"
        end

        text_children.map(&:text).join
      end

      # Override text_children to include EntityReference nodes.
      # EntityReference nodes should be treated as text-like for aggregation.
      def text_children
        children.select do |child|
          (child.text? && !child.cdata?) ||
            (child.is_a?(Lutaml::Xml::NokogiriElement) &&
             child.adapter_node.is_a?(::Nokogiri::XML::EntityReference))
        end
      end

      # Override cdata to ensure it always returns a String, not an Array
      # The base XmlElement.cdata has a bug where it returns
      # cdata_children.map(&:text) when children.count > 1 (Array instead of joined String)
      def cdata
        return @text if children.empty?
        # Always join to ensure we return a String, not an Array
        cdata_children.map(&:text).join
      end

      # Performance: Build attributes hash, return frozen empty when no attributes
      def build_attributes_hash(node)
        return EMPTY_ATTRIBUTES if node.attribute_nodes.empty?

        attributes = {}
        node.attribute_nodes.each do |attr|
          name = if attr.namespace
                   "#{attr.namespace.prefix}:#{attr.name}"
                 else
                   attr.name
                 end

          attributes[name] = XmlAttribute.new(
            name,
            attr.value,
            namespace: attr.namespace&.href,
            namespace_prefix: attr.namespace&.prefix,
          )
        end
        attributes
      end

      def to_xml
        # For text/cdata nodes and EntityReference, use the native Nokogiri
        # serialization which properly returns entity syntax
        return @adapter_node.to_xml if @adapter_node.is_a?(::Nokogiri::XML::EntityReference)

        # For text/cdata nodes, use the native Nokogiri serialization
        # which properly escapes entities
        return @adapter_node.to_xml if text? && @adapter_node.respond_to?(:to_xml)

        build_xml.doc.root.to_xml
      end

      def inner_xml
        children.map do |child|
          if child.is_a?(Lutaml::Xml::NokogiriElement) &&
             child.adapter_node.is_a?(::Nokogiri::XML::EntityReference)
            # For EntityReference children, use native to_xml which returns entity syntax
            child.adapter_node.to_xml
          else
            child.to_xml
          end
        end.join
      end

      def build_xml(builder = nil)
        builder ||= Builder::Nokogiri.build

        if @adapter_node.is_a?(::Nokogiri::XML::EntityReference)
          # EntityReference - create and add to parent
          entity_node = ::Nokogiri::XML::EntityReference.new(builder.doc, @adapter_node.name)
          builder.parent.add_child(entity_node)
        elsif cdata?
          # CDATA sections are handled differently
          # For now, treat them as text since Nokogiri builder handles CDATA
          builder.text(text)
        elsif text?
          # Actual text nodes get text output
          builder.text(text)
        else
          # Regular elements (including those named "text")
          # Handle element names that conflict with Nokogiri builder methods
          # (e.g., "text", "cdata", "comment") by appending underscore
          element_name = builder.respond_to?(name) ? "#{name}_" : name
          builder.public_send(element_name, build_attributes(self)) do |xml|
            children.each do |child|
              child.build_xml(xml)
            end
          end
        end

        builder
      end

      private

      def parse_children(node, root_node: nil)
        node.children.select(&:element?).map do |child|
          NokogiriElement.new(child, root_node: root_node)
        end
      end

      def parse_all_children(node, root_node: nil, default_namespace: nil)
        # Consolidate adjacent text-like nodes to fix entity fragmentation issue
        consolidated = consolidate_text_nodes(node.children)

        consolidated.map do |child|
          NokogiriElement.new(child, root_node: root_node,
                                     parent_document: self,
                                     default_namespace: default_namespace)
        end
      end

      def build_attributes(node, _options = {})
        attrs = node.attributes.transform_values(&:value)

        attrs.merge(build_namespace_attributes(node))
      end

      def build_namespace_attributes(node)
        # Performance: Use merge! to avoid creating intermediate hashes
        namespace_attrs = {}

        node.own_namespaces.each_value do |namespace|
          uri = namespace.uri
          # Convert FPI to URN per RFC 3151 (Nokogiri requires valid namespace URIs)
          uri = XmlElement.fpi_to_urn(uri) if XmlElement.fpi?(uri)
          namespace_attrs[namespace.attr_name] = uri
        end

        node.children.each do |child|
          # Performance: Use merge! instead of merge to avoid allocation
          build_namespace_attributes(child).each do |key, value|
            namespace_attrs[key] ||= value
          end
        end

        namespace_attrs
      end
    end
  end
end
