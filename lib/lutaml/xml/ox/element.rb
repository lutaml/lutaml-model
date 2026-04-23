# frozen_string_literal: true

module Lutaml
  module Xml
    module Ox
      class Element < XmlElement
        # Use NamespaceData for adapter-internal namespace data
        NamespaceData = Lutaml::Xml::Adapter::NamespaceData

        def initialize(node, parent: nil, default_namespace: nil)
          @moxml_node = node
          explicit_no_namespace = false

          # Determine node type from Moxml classification
          node_type = case node
                      when Moxml::Text then :text
                      when Moxml::Cdata then :cdata
                      when Moxml::Comment then :comment
                      else :element
                      end

          text = case node
                 when Moxml::Element
                   namespace_name = node.namespace&.prefix

                   # Cache namespace definitions
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

                   default_namespace = node.namespace&.uri if parent.nil? && !namespace_name && node.namespace&.uri != ""

                   children = parse_children(node,
                                             default_namespace: default_namespace)
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

          name = Lutaml::Xml::Adapter::OxAdapter.name_of(node)
          super(
            node,
            Hash(attributes),
            Array(children),
            text,
            name: name,
            parent_document: parent,
            namespace_prefix: namespace_name,
            default_namespace: default_namespace,
            explicit_no_namespace: explicit_no_namespace,
            node_type: node_type
          )
        end

        def text?
          # Text nodes have node_type == :text or :cdata
          %i[text cdata].include?(@node_type)
        end

        def text
          super || @text
        end

        def to_xml(_builder = nil)
          @moxml_node.to_xml(declaration: false, expand_empty: false)
        end

        def build_xml(builder = nil)
          builder ||= Builder::Ox.build

          if comment?
            builder.add_comment(builder.current_node, @text)
          elsif cdata?
            builder.add_text(builder.current_node, @text, cdata: true)
          elsif text? && !element?
            builder.add_text(builder.current_node, @text)
          else
            # Regular elements (including those named "text")
            attrs = build_attributes(self)
            builder.create_and_add_element(name, attributes: attrs) do |el|
              children.each { |child| child.build_xml(el) }
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

            ns_prefix = attr.namespace&.prefix
            name = if ns_prefix && !ns_prefix.empty?
                     "#{ns_prefix}:#{attr.name}"
                   else
                     attr.name
                   end

            # W3C: Attributes without prefix are NOT in any namespace
            # (even if parent element has a default namespace)
            namespace_uri = ns_prefix && !ns_prefix.empty? ? attr.namespace&.uri : nil

            hash[name] = XmlAttribute.new(
              name,
              attr.value,
              namespace: namespace_uri,
              namespace_prefix: ns_prefix && !ns_prefix.empty? ? ns_prefix : nil,
            )
          end
        end

        def parse_children(node, default_namespace: nil)
          node.children.filter_map do |child|
            next if child.is_a?(Moxml::ProcessingInstruction)

            self.class.new(child, parent: self,
                                  default_namespace: default_namespace)
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
end
