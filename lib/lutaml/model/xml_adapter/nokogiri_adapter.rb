# lib/lutaml/model/xml_adapter/nokogiri_adapter.rb
require "nokogiri"
require_relative "../xml_adapter"

module Lutaml
  module Model
    module XmlAdapter
      class NokogiriDocument < Document
        def self.parse(xml)
          parsed = Nokogiri::XML(xml)
          root = NokogiriElement.new(parsed.root)
          new(root)
        end

        def initialize(root)
          @root = root
        end

        def to_h
          # { @root.name => parse_element(@root) }
          parse_element(@root)
        end

        def to_xml(options = {})
          builder = Nokogiri::XML::Builder.new do |xml|
            build_element(xml, @root, options)
          end

          xml_data = builder.doc.root.to_xml(options[:pretty] ? { indent: 2 } : {})
          options[:declaration] ? declaration(options) + xml_data : xml_data
        end

        private

        def build_element(xml, element, _options = {})
          return element.to_xml(xml) if element.is_a?(Lutaml::Model::XmlAdapter::NokogiriElement)

          xml_mapping = element.class.mappings_for(:xml)
          return xml unless xml_mapping

          attributes = build_attributes(element, xml_mapping)

          prefixed_xml = xml_mapping.namespace_prefix ? xml[xml_mapping.namespace_prefix] : xml

          prefixed_xml.send(xml_mapping.root_element, attributes) do
            xml_mapping.elements.each do |element_rule|
              if element_rule.delegate
                attribute_def = element.send(element_rule.delegate).class.attributes[element_rule.to]
                value = element.send(element_rule.delegate).send(element_rule.to)
              else
                attribute_def = element.class.attributes[element_rule.to]
                value = element.send(element_rule.to)
              end

              prefixed_xml = element_rule.prefix ? xml[element_rule.prefix] : xml

              val = if attribute_def.collection?
                      value
                    elsif !value.nil? || element_rule.render_nil?
                      [value]
                    else
                      []
                    end

              val.each do |v|
                if attribute_def&.type&.<= Lutaml::Model::Serialize
                  handle_nested_elements(xml, element_rule, v)
                else
                  prefixed_xml.send(element_rule.name) do
                    if !v.nil?
                      serialized_value = attribute_def.type.serialize(v)

                      if attribute_def.type == Lutaml::Model::Type::Hash
                        serialized_value.each do |key, val|
                          xml.send(key) { xml.text val }
                        end
                      else
                        xml.text(serialized_value)
                      end
                    end
                  end
                end
              end
            end
            prefixed_xml.text element.text unless xml_mapping.elements.any?
          end
        end

        def handle_nested_elements(xml, _element_rule, value)
          case value
          when Array
            value.each { |val| build_element(xml, val) }
          else
            build_element(xml, value)
          end
        end

        def parse_element(element)
          result = element.children.each_with_object({}) do |child, hash|
            value = if child.text?
                      child.text
                    else
                      parse_element(child)
                    end

            if hash[child.unprefixed_name]
              hash[child.unprefixed_name] =
                [hash[child.unprefixed_name], value].flatten
            else
              hash[child.unprefixed_name] = value
            end
          end

          element.attributes.each do |name, attr|
            result[name] = attr.value
          end

          # result["_text"] = element.text if element.text
          result
        end
      end

      class NokogiriElement < Element
        def initialize(node, root_node: nil)
          if root_node
            node.namespaces.each do |prefix, name|
              namespace = Lutaml::Model::XmlNamespace.new(name, prefix)

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

            attributes[name] =
              Attribute.new(name, attr.value, namespace: attr.namespace&.href,
                                              namespace_prefix: attr.namespace&.prefix)
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
            attrs = build_attributes(self)

            builder.send(name, attrs) do |xml|
              children.each do |child|
                child.to_xml(xml)
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

          return namespace_attrs if node.children.empty?

          node.children.each do |child|
            namespace_attrs = namespace_attrs.merge(build_namespace_attributes(child))
          end

          namespace_attrs
        end
      end
    end
  end
end
