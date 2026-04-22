# frozen_string_literal: true

module Lutaml
  module Xml
    # NokogiriElement wraps Moxml nodes (Moxml::Element, Moxml::Text,
    # Moxml::Cdata) into the XmlElement interface used by lutaml-model.
    #
    # Entity references (&copy;, &nbsp;, etc.) are preserved natively
    # by moxml — entity preprocessing and restoration is handled
    # consistently across all adapters at the moxml level.
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

        @moxml_node = node

        text = case node
               when Moxml::Element
                 namespace_name = node.namespace&.prefix

                 # Cache namespace definitions to avoid repeated Moxml wrapper allocations
                 ns_defs = node.namespaces

                 # Detect explicit xmlns="" for no namespace
                 has_empty_xmlns = ns_defs.any? do |ns|
                   ns.prefix.nil? && ns.uri == ""
                 end

                 explicit_no_namespace = XmlElement.detect_explicit_no_namespace(
                   has_empty_xmlns: has_empty_xmlns,
                   node_namespace_nil: node.namespace.nil? || node.namespace&.uri == "",
                 )

                 add_namespaces_from_defs(ns_defs, is_root: parent.nil?)

                 if parent.nil? && !namespace_name && node.namespace&.uri &&
                     node.namespace.uri != ""
                   default_namespace = node.namespace.uri
                 end

                 children = parse_children(node,
                                           default_namespace: default_namespace)
                 attributes = node_attributes(node)
                 @root = node
                 EncodingNormalizer.normalize_to_utf8(node.inner_text)
               when Moxml::Text
                 # Store raw content (with entity markers) for DOM reconstruction
                 @raw_text = node.respond_to?(:raw_content) ? node.raw_content : node.content
                 EncodingNormalizer.normalize_to_utf8(node.content)
               when Moxml::Cdata
                 EncodingNormalizer.normalize_to_utf8(node.content)
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

      def to_xml(_builder = nil)
        @moxml_node.to_xml(declaration: false, expand_empty: false)
      end

      def build_xml(builder = nil)
        builder ||= Builder::Nokogiri.build

        if cdata?
          builder.add_cdata(builder.xml.parent, @text.to_s)
        elsif text? && !element?
          # Use raw text (with entity markers) so moxml's serialize → restore
          # can convert them back to named entity references
          builder.add_text(builder.xml.parent, (@raw_text || @text).to_s)
        else
          builder.create_and_add_element(name,
                                         prefix: namespace_prefix,
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

      def node_attributes(node)
        node.attributes.each_with_object({}) do |attr, hash|
          next if attr_is_namespace?(attr)

          attr_name = if attr.namespace
                        "#{attr.namespace.prefix}:#{attr.name}"
                      else
                        attr.name
                      end
          # Use raw_value (with entity markers) so build_xml can pass them
          # through to moxml's serialize → restore_entities pipeline.
          attr_val = attr.respond_to?(:raw_value) ? attr.raw_value : attr.value
          hash[attr_name] = XmlAttribute.new(
            attr_name,
            attr_val,
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
        add_namespaces_from_defs(node.namespaces, is_root: is_root)
      end

      def add_namespaces_from_defs(ns_defs, is_root: false)
        has_default_xmlns = is_root || ns_defs.any? { |ns| ns.prefix.nil? }

        ns_defs.each do |namespace|
          ns = NamespaceData.new(namespace.uri, namespace.prefix)
          add_namespace(ns) if ns.prefix || has_default_xmlns
        end
      end
      private :add_namespaces_from_defs

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
