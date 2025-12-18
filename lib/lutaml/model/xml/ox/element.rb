# frozen_string_literal: true

require_relative "../xml_element"
require_relative "../xml_attribute"
require_relative "../xml_namespace"

module Lutaml
  module Model
    module Xml
      class OxElement < XmlElement
        def initialize(node, root_node: nil, default_namespace: nil)
          case node
          when String
            super("text", {}, [], node, parent_document: root_node, name: "text", explicit_no_namespace: false)
          when Ox::Comment
            super("comment", {}, [], node.value, parent_document: root_node, name: "comment", explicit_no_namespace: false)
          when Ox::CData
            super("#cdata-section", {}, [], node.value, parent_document: root_node, name: "#cdata-section", explicit_no_namespace: false)
          else
            # Check for xmlns="" in node's attributes before processing
            has_empty_xmlns = node.attributes[:xmlns] == ""
            has_no_prefix = separate_name_and_prefix(node).first.nil?

            namespace_attributes(node.attributes).each do |(name, value)|
              ns = XmlNamespace.new(value, name)

              if root_node && ns.prefix
                root_node.add_namespace(ns)
              elsif root_node.nil?
                add_namespace(ns)
              end

              # Set default_namespace from xmlns attribute (if not empty)
              default_namespace = ns.uri if ns.prefix.nil? && value != ""
            end

            # Use shared helper to detect explicit no namespace
            explicit_no_namespace = XmlElement.detect_explicit_no_namespace(
              has_empty_xmlns: has_empty_xmlns,
              node_namespace_nil: has_no_prefix, # Ox nodes without prefix have no namespace
            )

            attributes = node.attributes.each_with_object({}) do |(name, value), hash|
              next if attribute_is_namespace?(name)

              namespace_prefix = name.to_s.split(":").first
              if (n = name.to_s.split(":")).length > 1
                namespace = (root_node || self).namespaces[namespace_prefix]&.uri
                namespace ||= XML_NAMESPACE_URI
                prefix = n.first
              end

              hash[name.to_s] = XmlAttribute.new(
                name.to_s,
                value,
                namespace: namespace,
                namespace_prefix: prefix,
              )
            end

            prefix, name = separate_name_and_prefix(node)

            super(
              node,
              attributes,
              parse_children(node, root_node: root_node || self,
                                   default_namespace: default_namespace),
              node.text,
              parent_document: root_node,
              name: name,
              namespace_prefix: prefix,
              default_namespace: default_namespace,
              explicit_no_namespace: explicit_no_namespace
            )
          end
        end

        def separate_name_and_prefix(node)
          name = node.name.to_s

          return [nil, name] unless name.include?(":")
          return [nil, name] if name.start_with?("xmlns:")

          prefix, _, name = name.partition(":")
          [prefix, name]
        end

        def to_xml
          return text if text?

          build_xml.xml.to_s
        end

        def inner_xml
          # Ox builder by default, adds a newline at the end, so `chomp` is used
          children.map { |child| child.to_xml.chomp }.join
        end

        def build_xml(builder = nil)
          builder ||= Builder::Ox.build
          attrs = build_attributes(self)

          if text?
            builder.add_text(builder, text)
          else
            builder.create_and_add_element(name, attributes: attrs) do |el|
              children.each { |child| child.build_xml(el) }
            end
          end

          builder
        end

        def namespace_attributes(attributes)
          attributes.select { |attr| attribute_is_namespace?(attr) }
        end

        def text?
          # false
          children.empty? && text&.length&.positive?
        end

        def build_attributes(node)
          attrs = node.attributes.transform_values(&:value)

          node.own_namespaces.each_value do |namespace|
            attrs[namespace.attr_name] = namespace.uri
          end

          attrs
        end

        def nodes
          children
        end

        def cdata
          super || cdata_children.first&.text
        end

        def text
          super || cdata
        end

        private

        def parse_children(node, root_node: nil, default_namespace: nil)
          node.nodes.map do |child|
            OxElement.new(child, root_node: root_node,
                                 default_namespace: default_namespace)
          end
        end
      end
    end
  end
end