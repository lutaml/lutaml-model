# frozen_string_literal: true

require_relative "../xml_element"
require_relative "../xml_attribute"
require_relative "../xml_namespace"
require_relative "entity_resolver"
require_relative "../encoding_normalizer"

module Lutaml
  module Model
    module Xml
      class NokogiriElement < XmlElement
        include Nokogiri::EntityResolver

        def initialize(node, root_node: nil, default_namespace: nil)
          if root_node
            node.namespaces.each do |prefix, name|
              namespace = XmlNamespace.new(name, prefix)

              root_node.add_namespace(namespace)
            end
          end

          attributes = {}

          # Using `attribute_nodes` instead of `attributes` because
          # `attribute_nodes` handles name collisions as well
          # More info: https://devdocs.io/nokogiri/nokogiri/xml/node#method-i-attribute_nodes
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

          # Detect if xmlns="" is explicitly set (explicit no namespace)
          # Use shared helper method for consistency across all adapters
          explicit_no_namespace = XmlElement.detect_explicit_no_namespace(
            has_empty_xmlns: node.namespaces.key?("xmlns") && node.namespaces["xmlns"] == "",
            node_namespace_nil: node.namespace.nil?,
          )

          # Set default namespace for root, or inherit from parent for children
          if !node.namespace&.prefix
            default_namespace = node.namespace&.href ||
              root_node&.instance_variable_get(:@default_namespace)
          end

          super(
            node,
            attributes,
            parse_all_children(node, root_node: root_node || self,
                                     default_namespace: default_namespace),
            EncodingNormalizer.normalize_to_utf8(node.text),
            name: node.name,
            parent_document: root_node,
            namespace_prefix: node.namespace&.prefix,
            default_namespace: default_namespace,
            explicit_no_namespace: explicit_no_namespace
          )
        end

        def text?
          # false
          children.empty? && text.length.positive?
        end

        def to_xml
          return text if text?

          build_xml.doc.root.to_xml
        end

        def inner_xml
          children.map(&:to_xml).join
        end

        def build_xml(builder = nil)
          builder ||= Builder::Nokogiri.build

          if name == "text"
            builder.text(text)
          else
            builder.public_send(name, build_attributes(self)) do |xml|
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
                                       default_namespace: default_namespace)
          end
        end

        def build_attributes(node, _options = {})
          attrs = node.attributes.transform_values(&:value)

          attrs.merge(build_namespace_attributes(node))
        end

        def build_namespace_attributes(node)
          namespace_attrs = {}

          node.own_namespaces.each_value do |namespace|
            namespace_attrs[namespace.attr_name] = namespace.uri
          end

          node.children.each do |child|
            namespace_attrs = namespace_attrs.merge(
              build_namespace_attributes(child),
            )
          end

          namespace_attrs
        end
      end
    end
  end
end