# frozen_string_literal: true

module Lutaml
  module Xml
    # NokogiriElement wraps Moxml nodes (Moxml::Element, Moxml::Text,
    # Moxml::Cdata) into the XmlElement interface used by lutaml-model.
    #
    # Entity references (&copy;, &nbsp;, etc.) are preserved via a
    # pre-processing marker approach in NokogiriAdapter.parse, since
    # Moxml v0.1.x does not yet have a Moxml::EntityReference node type.
    # TODO: Replace marker approach with Moxml::EntityReference once available.
    class NokogiriElement < XmlElement
      # Use NamespaceData for adapter-internal namespace data
      NamespaceData = Lutaml::Xml::Adapter::NamespaceData

      def initialize(node, parent: nil, default_namespace: nil)
        # Determine node type from Moxml classification
        node_type = case node
                    when Moxml::Cdata then :cdata
                    when Moxml::Text then :text
                    when Moxml::Comment then :comment
                    else :element
                    end

        text = case node
               when Moxml::Element
                 namespace_name = node.namespace&.prefix

                 # Detect explicit xmlns="" for no namespace
                 has_empty_xmlns = node.namespaces.any? do |ns|
                   ns.prefix.nil? && ns.uri == ""
                 end

                 explicit_no_namespace = XmlElement.detect_explicit_no_namespace(
                   has_empty_xmlns: has_empty_xmlns,
                   node_namespace_nil: node.namespace.nil? || node.namespace&.uri == "",
                 )

                 add_namespaces(node, is_root: parent.nil?)

                 if parent.nil? && !namespace_name && node.namespace&.uri &&
                     node.namespace.uri != ""
                   default_namespace = node.namespace.uri
                 end

                 children = parse_children(node,
                                           default_namespace: default_namespace)
                 attributes = node_attributes(node)
                 @root = node
                 restore_entities(
                   EncodingNormalizer.normalize_to_utf8(node.inner_text),
                 )
               when Moxml::Text
                 restore_entities(
                   EncodingNormalizer.normalize_to_utf8(node.content),
                 )
               when Moxml::Cdata
                 restore_entities(
                   EncodingNormalizer.normalize_to_utf8(node.content),
                 )
               end

        name = Lutaml::Xml::Adapter::NokogiriAdapter.name_of(node)
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

      def to_xml(builder = nil)
        # For text and cdata nodes return content directly
        return @text.to_s if text? || cdata?

        builder ||= Builder::Nokogiri.build
        build_xml(builder)
        builder.doc.root ? builder.doc.root.to_xml : ""
      end

      def build_xml(builder = nil)
        builder ||= Builder::Nokogiri.build

        if cdata?
          builder.add_cdata(builder.xml.parent, @text.to_s)
        elsif text? && !element?
          builder.add_text(builder.xml.parent, @text.to_s)
        else
          builder.create_and_add_element(name,
                                         attributes: build_attributes(self)) do |xml|
            children.each { |child| child.build_xml(xml) }
          end
        end

        builder
      end

      def inner_xml
        children.map(&:to_xml).join
      end

      private

      # Restore entity markers back to &name; syntax.
      # See NokogiriAdapter::ENTITY_MARKER for details.
      def restore_entities(text)
        Lutaml::Xml::Adapter::NokogiriAdapter.restore_entities(text)
      end

      def node_attributes(node)
        node.attributes.each_with_object({}) do |attr, hash|
          next if attr_is_namespace?(attr)

          attr_name = if attr.namespace
                        "#{attr.namespace.prefix}:#{attr.name}"
                      else
                        attr.name
                      end
          hash[attr_name] = XmlAttribute.new(
            attr_name,
            attr.value,
            namespace: attr.namespace&.uri,
            namespace_prefix: attr.namespace&.prefix,
          )
        end
      end

      def parse_children(node, default_namespace: nil)
        node.children.filter_map do |child|
          next if child.is_a?(Moxml::ProcessingInstruction)
          next if child.is_a?(Moxml::Comment)

          self.class.new(child, parent: self,
                                default_namespace: default_namespace)
        end
      end

      def add_namespaces(node, is_root: false)
        has_default_xmlns = is_root || node.namespaces.any? do |ns|
          ns.prefix.nil?
        end

        node.namespaces.each do |namespace|
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

        node.children.each do |child|
          build_namespace_attributes(child).each do |key, value|
            namespace_attrs[key] ||= value
          end
        end

        namespace_attrs
      end
    end
  end
end
