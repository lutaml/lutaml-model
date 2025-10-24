# frozen_string_literal: true

require_relative "../xml_element"

module Lutaml
  module Model
    module Xml
      module Oga
        class Element < XmlElement
          def initialize(node, parent: nil, default_namespace: nil)
            text, attributes, children, namespace_name, updated_namespace = if node.is_a?(Moxml::Element)
                                                                              initialize_element(node, parent, default_namespace)
                                                                            else
                                                                              [node.content, nil, nil, nil, default_namespace]
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
              default_namespace: updated_namespace,
            )

            # Add default namespace to namespaces hash so it's accessible via default_namespace getter
            # Only add if it's not root (root's default namespace is already added by add_namespaces)
            add_namespace(updated_namespace) if should_add_default_namespace?(updated_namespace, namespace_name, parent)
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

          def initialize_element(node, parent, default_namespace)
            namespace_name = node.namespace&.prefix
            add_namespaces(node, is_root: parent.nil?)

            updated_namespace = update_default_namespace(node, parent, namespace_name, default_namespace)

            children = parse_children(node, default_namespace: updated_namespace)
            attributes = node_attributes(node)
            @root = node

            [node.inner_text, attributes, children, namespace_name, updated_namespace]
          end

          def update_default_namespace(node, parent, namespace_name, default_namespace)
            return default_namespace if namespace_name || !node.namespace&.uri

            should_update = parent.nil? || node.namespace.uri != default_namespace&.uri
            should_update ? XmlNamespace.new(node.namespace.uri, nil) : default_namespace
          end

          def should_add_default_namespace?(default_namespace, namespace_name, parent)
            default_namespace&.uri && !namespace_name && parent
          end

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
            node.children.map { |child| self.class.new(child, parent: self, default_namespace: default_namespace) }
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
