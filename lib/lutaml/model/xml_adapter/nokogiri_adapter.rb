require "nokogiri"
require_relative "xml_document"

module Lutaml
  module Model
    module XmlAdapter
      class NokogiriAdapter < XmlDocument
        def self.parse(xml)
          parsed = Nokogiri::XML(xml)
          root = NokogiriElement.new(parsed.root)
          new(root)
        end

        def to_xml(options = {})
          builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
            if root.is_a?(Lutaml::Model::XmlAdapter::NokogiriElement)
              root.to_xml(xml)
            else
              mapper_class = options[:mapper_class] || @root.class
              options[:xml_attributes] = build_namespace_attributes(mapper_class)
              build_element(xml, @root, options)
            end
          end

          xml_options = {}
          xml_options[:indent] = 2 if options[:pretty]

          xml_data = builder.doc.root.to_xml(xml_options)
          options[:declaration] ? declaration(options) + xml_data : xml_data
        end

        private

        def build_unordered_element(xml, element, options = {})
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml)
          return xml unless xml_mapping

          attributes = options[:xml_attributes] ||= {}
          attributes = build_attributes(element,
                                        xml_mapping).merge(attributes)&.compact

          prefixed_xml = if options.key?(:namespace_prefix)
                           options[:namespace_prefix] ? xml[options[:namespace_prefix]] : xml
                         elsif xml_mapping.namespace_prefix
                           xml[xml_mapping.namespace_prefix]
                         else
                           xml
                         end

          tag_name = options[:tag_name] || xml_mapping.root_element
          prefixed_xml.public_send(tag_name, attributes) do
            if options.key?(:namespace_prefix) && !options[:namespace_prefix]
              xml.parent.namespace = nil
            end

            xml_mapping.elements.each do |element_rule|
              attribute_def = attribute_definition_for(element, element_rule, mapper_class: mapper_class)
              value = attribute_value_for(element, element_rule)

              next if value.nil? && !element_rule.render_nil?

              nsp_xml = element_rule.prefix ? xml[element_rule.prefix] : xml

              if attribute_def.collection?
                value.each do |v|
                  add_to_xml(nsp_xml, v, attribute_def, element_rule)
                end
              elsif !value.nil? || element_rule.render_nil?
                add_to_xml(nsp_xml, value, attribute_def, element_rule)
              end
            end

            if xml_mapping.content_mapping
              text = element.send(xml_mapping.content_mapping.to)
              text = text.join if text.is_a?(Array)

              prefixed_xml.text text
            end
          end
        end

        def build_ordered_element(xml, element, options = {})
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml)
          return xml unless xml_mapping

          attributes = build_attributes(element, xml_mapping)&.compact

          prefixed_xml = if options.key?(:namespace_prefix)
                           options[:namespace_prefix] ? xml[options[:namespace_prefix]] : xml
                         elsif xml_mapping.namespace_prefix
                           xml[xml_mapping.namespace_prefix]
                         else
                           xml
                         end

          tag_name = options[:tag_name] || xml_mapping.root_element
          prefixed_xml.public_send(tag_name, attributes) do
            if options.key?(:namespace_prefix) && !options[:namespace_prefix]
              xml.parent.namespace = nil
            end

            index_hash = {}

            element.element_order.each do |name|
              index_hash[name] ||= -1
              curr_index = index_hash[name] += 1

              element_rule = xml_mapping.find_by_name(name)
              next if element_rule.nil?

              attribute_def = attribute_definition_for(element, element_rule, mapper_class: mapper_class)
              value = attribute_value_for(element, element_rule)
              nsp_xml = element_rule.prefix ? xml[element_rule.prefix] : xml

              if element_rule == xml_mapping.content_mapping
                text = element.send(xml_mapping.content_mapping.to)
                text = text[curr_index] if text.is_a?(Array)

                prefixed_xml.text text
              elsif attribute_def.collection?
                add_to_xml(nsp_xml, value[curr_index], attribute_def,
                           element_rule)
              elsif !value.nil? || element_rule.render_nil?
                add_to_xml(nsp_xml, value, attribute_def, element_rule)
              end
            end
          end
        end

        def add_to_xml(xml, value, attribute, rule)
          if value && (attribute&.type&.<= Lutaml::Model::Serialize)
            handle_nested_elements(
              xml,
              value,
              rule: rule,
              attribute: attribute,
            )
          else
            xml.public_send(rule.name) do
              if !value.nil?
                serialized_value = attribute.type.serialize(value)

                if attribute.type == Lutaml::Model::Type::Hash
                  serialized_value.each do |key, val|
                    xml.public_send(key) { xml.text val }
                  end
                else
                  xml.text(serialized_value)
                end
              end
            end
          end
        end
      end

      class NokogiriElement < XmlElement
        def initialize(node, root_node: nil)
          if root_node
            node.namespaces.each do |prefix, name|
              namespace = XmlNamespace.new(name, prefix)

              root_node.add_namespace(namespace)
            end
          end

          attributes = {}
          node.attributes.transform_values do |attr|
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

          super(
            node.name,
            attributes,
            parse_all_children(node, root_node: root_node || self),
            node.text,
            parent_document: root_node,
            namespace_prefix: node.namespace&.prefix,
          )
        end

        def text?
          # false
          children.empty? && text.length.positive?
        end

        def to_xml(builder = nil)
          builder ||= Nokogiri::XML::Builder.new

          if name == "text"
            builder.text(text)
          else
            builder.send(name, build_attributes(self)) do |xml|
              children.each { |child| child.to_xml(xml) }
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

        def parse_all_children(node, root_node: nil)
          node.children.map do |child|
            NokogiriElement.new(child, root_node: root_node)
          end
        end

        def build_attributes(node)
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
