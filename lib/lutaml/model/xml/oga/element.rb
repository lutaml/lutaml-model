# frozen_string_literal: true

require_relative "../xml_element"

module Lutaml
  module Model
    module Xml
      module Oga
        class Element < XmlElement
          def initialize(node, parent: nil, default_namespace: nil)
            explicit_no_namespace = false

            text = case node
                   when Moxml::Element
                     namespace_name = node.namespace&.prefix

                     # Detect explicit xmlns="" for no namespace
                     # Oga reports this as namespace with name="xmlns" and uri=""
                     has_empty_xmlns = node.namespaces.any? do |ns|
                       (ns.prefix.nil? || ns.name == "xmlns") && ns.uri == ""
                     end

                     explicit_no_namespace = XmlElement.detect_explicit_no_namespace(
                       has_empty_xmlns: has_empty_xmlns,
                       node_namespace_nil: node.namespace.nil? || node.namespace&.uri == ""
                     )

                     add_namespaces(node, is_root: parent.nil?)

                     default_namespace = node.namespace&.uri if parent.nil? && !namespace_name && node.namespace&.uri != ""

                     children = parse_children(node,
                                               default_namespace: default_namespace)
                     attributes = node_attributes(node)
                     @root = node
                     node.inner_text
                   when Moxml::Text
                     node.content
                   end

            name = OgaAdapter.name_of(node)
            super(
              name,
              Hash(attributes),
              Array(children),
              text,
              name: name,
              parent_document: parent,
              namespace_prefix: namespace_name,
              default_namespace: default_namespace,
              explicit_no_namespace: explicit_no_namespace
            )
          end

          def text?
            children.empty? && text&.length&.positive?
          end

          def text
            super || @text
          end

          def to_xml(builder = Builder::Oga.build)
            build_xml(builder).to_xml
          end

          def build_xml(builder = Builder::Oga.build)
            if name == "text"
              builder.add_text(builder.current_node, @text)
            else
              builder.create_element(name, build_attributes(self)) do |xml|
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

              name = if attr.namespace
                       "#{attr.namespace.prefix}:#{attr.name}"
                     else
                       attr.name
                     end
              hash[name] = XmlAttribute.new(
                name,
                attr.value,
                namespace: attr.namespace&.uri,
                namespace_prefix: attr.namespace&.prefix,
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

          def add_namespaces(node, is_root: false)
            node.namespaces.each do |namespace|
              ns = XmlNamespace.new(namespace.uri, namespace.prefix)

              if ns.prefix || is_root
                add_namespace(ns)
              end
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
end
