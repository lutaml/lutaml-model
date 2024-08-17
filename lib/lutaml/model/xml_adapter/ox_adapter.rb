require "ox"
require_relative "xml_document"

module Lutaml
  module Model
    module XmlAdapter
      class OxAdapter < XmlDocument
        def self.parse(xml)
          parsed = Ox.parse(xml)
          root = OxElement.new(parsed)
          new(root)
        end

        def to_xml(options = {})
          builder = Ox::Builder.new

          if @root.is_a?(Lutaml::Model::XmlAdapter::OxElement)
            @root.to_xml(builder)
          elsif ordered?(@root, options)
            build_ordered_element(builder, @root, options)
          else
            build_element(builder, @root, options)
          end

          # xml_data = Ox.dump(builder)
          xml_data = builder.to_s
          options[:declaration] ? declaration(options) + xml_data : xml_data
        end

        private

        def build_unordered_element(builder, element, options = {})
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml)
          return xml unless xml_mapping

          attributes = build_attributes(element, xml_mapping).compact

          tag_name = options[:tag_name] || xml_mapping.root_element
          prefixed_name = if options.key?(:namespace_prefix)
                            [options[:namespace_prefix], tag_name].compact.join(":")
                          elsif xml_mapping.namespace_prefix
                            "#{xml_mapping.namespace_prefix}:#{tag_name}"
                          else
                            tag_name
                          end

          builder.element(prefixed_name, attributes) do |el|
            xml_mapping.elements.each do |element_rule|
              attribute_def = attribute_definition_for(element, element_rule, mapper_class: mapper_class)
              value = attribute_value_for(element, element_rule)

              val = if attribute_def.collection?
                      value
                    elsif value || element_rule.render_nil?
                      [value]
                    else
                      []
                    end

              val.each do |v|
                if attribute_def&.type&.<= Lutaml::Model::Serialize
                  handle_nested_elements(el, v, rule: element_rule, attribute: attribute_def)
                else
                  builder.element(element_rule.prefixed_name) do |el|
                    el.text(attribute_def.type.serialize(v)) if v
                  end
                end
              end
            end

            if (content_rule = xml_mapping.content_mapping)
              text = element.send(xml_mapping.content_mapping.to)
              text = text.join if text.is_a?(Array)

              if content_rule.custom_methods[:to]
                text = @root.send(content_rule.custom_methods[:to], @root, text)
              end

              el.text text
            end
          end
        end

        def build_ordered_element(builder, element, options = {})
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml)
          return xml unless xml_mapping

          attributes = build_attributes(element, xml_mapping).compact

          tag_name = options[:tag_name] || xml_mapping.root_element
          builder.element(tag_name, attributes) do |el|
            index_hash = {}

            element.element_order.each do |name|
              index_hash[name] ||= -1
              curr_index = index_hash[name] += 1

              element_rule = xml_mapping.find_by_name(name)

              attribute_def = attribute_definition_for(element, element_rule, mapper_class: mapper_class)
              value = attribute_value_for(element, element_rule)

              if element_rule == xml_mapping.content_mapping
                text = element.send(xml_mapping.content_mapping.to)
                text = text[curr_index] if text.is_a?(Array)

                el.text text
              elsif attribute_def.collection?
                add_to_xml(el, value[curr_index], attribute_def, element_rule)
              elsif !value.nil? || element_rule.render_nil?
                add_to_xml(el, value, attribute_def, element_rule)
              end
            end
          end
        end

        def add_to_xml(xml, value, attribute, rule)
          if rule.custom_methods[:to]
            value = @root.send(rule.custom_methods[:to], @root, value)
          end

          if value && (attribute&.type&.<= Lutaml::Model::Serialize)
            handle_nested_elements(
              xml,
              value,
              rule: rule,
              attribute: attribute,
            )
          else
            xml.element(rule.name) do |el|
              if !value.nil?
                serialized_value = attribute.type.serialize(value)

                if attribute.type == Lutaml::Model::Type::Hash
                  serialized_value.each do |key, val|
                    el.element(key) { |child_el| child_el.text val }
                  end
                else
                  el.text(serialized_value)
                end
              end
            end
          end
        end
      end

      class OxElement < XmlElement
        def initialize(node, root_node: nil)
          if node.is_a?(String)
            super("text", {}, [], node, parent_document: root_node)
          else
            namespace_attributes(node.attributes).each do |(name, value)|
              if root_node
                root_node.add_namespace(XmlNamespace.new(value, name))
              else
                add_namespace(XmlNamespace.new(value, name))
              end
            end

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

            super(
              node.name.to_s,
              attributes,
              parse_children(node, root_node: root_node || self),
              node.text,
              parent_document: root_node,
            )
          end
        end

        def to_xml(builder = nil)
          builder ||= Ox::Builder.new
          attrs = build_attributes(self)

          if text?
            builder.text(text)
          else
            builder.element(name, attrs) do |el|
              children.each { |child| child.to_xml(el) }
            end
          end
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

        private

        def parse_children(node, root_node: nil)
          node.nodes.map do |child|
            OxElement.new(child, root_node: root_node)
          end
        end
      end
    end
  end
end
