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
          { @root.name => parse_element(@root) }
        end

        def to_xml(options = {})
          builder = Nokogiri::XML::Builder.new do |xml|
            build_element(xml, @root, options)
          end

          xml_data = builder.to_xml(options[:pretty] ? { indent: 2 } : {})
          options[:declaration] ? declaration(options) + xml_data : xml_data
        end

        private

        def build_element(xml, element, options = {})
          xml_mapping = element.class.mappings_for(:xml)
          return xml unless xml_mapping

          attributes = build_attributes(element, xml_mapping)

          xml.send(xml_mapping.root_element, attributes) do
            xml_mapping.elements.each do |element_rule|
              attribute_def = element.class.attributes[element_rule.to]
              value = element.send(element_rule.to)

              if attribute_def&.type <= Lutaml::Model::Serialize
                handle_nested_elements(xml, element_rule, value)
              else
                xml.send(element_rule.name) { xml.text value }
              end
            end
            xml.text element.text unless xml_mapping.elements.any?
          end
        end

        def build_attributes(element, xml_mapping)
          xml_mapping.attributes.each_with_object(namespace_attributes(xml_mapping)) do |mapping_rule, hash|
            full_name = if mapping_rule.namespace
                "#{mapping_rule.prefix ? "#{mapping_rule.prefix}:" : ""}#{mapping_rule.name}"
              else
                mapping_rule.name
              end
            hash[full_name] = element.send(mapping_rule.to)
          end
        end

        def namespace_attributes(xml_mapping)
          return {} unless xml_mapping.namespace_uri

          if xml_mapping.namespace_prefix
            { "xmlns:#{xml_mapping.namespace_prefix}" => xml_mapping.namespace_uri }
          else
            { "xmlns" => xml_mapping.namespace_uri }
          end
        end

        def handle_nested_elements(xml, element_rule, value)
          case value
          when Array
            value.each { |val| build_element(xml, val) }
          else
            build_element(xml, value)
          end
        end

        def parse_element(element)
          result = element.children.each_with_object({}) do |child, hash|
            next if child.text?

            hash[child.name] ||= []
            hash[child.name] << parse_element(child)
          end
          result["_text"] = element.text if element.text?
          result
        end
      end

      class NokogiriElement < Element
        def initialize(node)
          attributes = node.attributes.transform_values do |attr|
            Attribute.new(attr.name, attr.value, namespace: attr.namespace&.href, namespace_prefix: attr.namespace&.prefix)
          end
          super(node.name, attributes, parse_children(node), node.text, namespace: node.namespace&.href, namespace_prefix: node.namespace&.prefix)
        end

        def text?
          false
        end

        private

        def parse_children(node)
          node.children.select(&:element?).map { |child| NokogiriElement.new(child) }
        end
      end
    end
  end
end
