# frozen_string_literal: true

module Lutaml
  module Xml
    # Base element wrapper for moxml-backed XML adapters.
    # NokogiriElement, Ox::Element, Oga::Element, Rexml::Element
    # all inherit from this class.
    class AdapterElement < XmlElement
      NamespaceData = Lutaml::Xml::Adapter::NamespaceData

      def initialize(node, parent: nil, default_namespace: nil)
        @moxml_node = node

        node_type = case node
                    when Moxml::Cdata then :cdata
                    when Moxml::Text then :text
                    when Moxml::Comment then :comment
                    else :element
                    end

        text = case node
               when Moxml::Element
                 namespace_name = node.namespace&.prefix
                 ns_defs = node.namespaces

                 has_empty_xmlns = ns_defs.any? { |ns| ns.prefix.nil? && ns.uri == "" }

                 explicit_no_namespace = XmlElement.detect_explicit_no_namespace(
                   has_empty_xmlns: has_empty_xmlns,
                   node_namespace_nil: node.namespace.nil? || node.namespace&.uri == "",
                 )

                 add_namespaces_from_defs(ns_defs, is_root: parent.nil?)

                 if parent.nil? && !namespace_name && node.namespace&.uri &&
                     node.namespace.uri != ""
                   default_namespace = node.namespace.uri
                 end

                 children = parse_children(node, default_namespace: default_namespace)
                 attributes = node_attributes(node)
                 @root = node
                 EncodingNormalizer.normalize_to_utf8(node.inner_text)
               when Moxml::Text
                 EncodingNormalizer.normalize_to_utf8(node.content)
               when Moxml::Cdata
                 EncodingNormalizer.normalize_to_utf8(node.content)
               when Moxml::Comment
                 EncodingNormalizer.normalize_to_utf8(node.content)
               end

        name = adapter_class.name_of(node)
        super(
          node,
          Hash(attributes),
          Array(children),
          text,
          name: name,
          parent_document: parent,
          namespace_prefix: namespace_name,
          default_namespace: default_namespace,
          explicit_no_namespace: explicit_no_namespace || false,
          node_type: node_type
        )
      end

      def text?
        %i[text cdata].include?(@node_type)
      end

      def text
        super || @text
      end

      def to_xml(_builder = nil)
        @moxml_node.to_xml(declaration: false, expand_empty: false)
      end

      def build_xml(builder = nil)
        if cdata?
          builder.add_text(builder.current_node, @text.to_s, cdata: true)
        elsif comment?
          builder.add_comment(builder.current_node, @text.to_s)
        elsif text? && !element?
          builder.add_text(builder.current_node, build_text_for_xml.to_s)
        else
          build_element_xml(builder)
        end

        builder
      end

      def inner_xml
        children.map(&:to_xml).join
      end

      private

      def build_element_xml(builder)
        builder.create_and_add_element(name,
                                       attributes: build_attributes(self)) do |xml|
          children.each { |child| child.build_xml(xml) }
        end
      end

      def build_text_for_xml
        @text
      end

      def adapter_class
        raise NotImplementedError, "#{self.class} must implement #adapter_class"
      end

      def node_attributes(node)
        return {} unless node.is_a?(Moxml::Element)

        node.attributes.each_with_object({}) do |attr, hash|
          next if attr_is_namespace?(attr)

          ns_prefix = attr.namespace&.prefix
          ns_prefix = nil if ns_prefix&.empty?

          attr_name = ns_prefix ? "#{ns_prefix}:#{attr.name}" : attr.name

          hash[attr_name] = XmlAttribute.new(
            attr_name,
            attribute_value_for_build(attr),
            namespace: ns_prefix ? attr.namespace&.uri : nil,
            namespace_prefix: ns_prefix,
          )
        end
      end

      def attribute_value_for_build(attr)
        attr.value
      end

      def parse_children(node, default_namespace: nil)
        return [] unless node.children

        node.children.filter_map do |child|
          next if child.is_a?(Moxml::ProcessingInstruction)
          next if (child.is_a?(Moxml::Text) || child.is_a?(Moxml::Cdata)) && child.content.empty?

          self.class.new(child, parent: self, default_namespace: default_namespace)
        end
      end

      def add_namespaces_from_defs(ns_defs, is_root: false)
        has_default_xmlns = is_root || ns_defs.any? { |ns| ns.prefix.nil? }

        ns_defs.each do |namespace|
          ns = NamespaceData.new(namespace.uri, namespace.prefix)
          add_namespace(ns) if ns.prefix || has_default_xmlns
        end
      end

      def attr_is_namespace?(attr)
        attribute_is_namespace?(attr.name) ||
          namespaces[attr.name]&.uri == attr.value
      end

      def build_attributes(node, _options = {})
        attrs = node.attributes.transform_values(&:value)
        attrs.merge(build_namespace_attributes(node))
      end

      def build_namespace_attributes(node)
        namespace_attrs = {}

        node.own_namespaces.each_value do |namespace|
          uri = namespace.uri
          uri = XmlElement.fpi_to_urn(uri) if XmlElement.fpi?(uri)
          namespace_attrs[namespace.attr_name] = uri
        end

        namespace_attrs
      end
    end
  end
end
