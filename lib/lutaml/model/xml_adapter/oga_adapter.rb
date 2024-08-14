require "oga"
require_relative "xml_document"

module Lutaml
  module Model
    module XmlAdapter
      class OgaAdapter < XmlDocument
        def self.parse(xml)
          parsed = Oga.parse_xml(xml)
          root = OgaElement.new(parsed)
          new(root)
        end

        def to_h
          { @root.name => parse_element(@root) }
        end

        def to_xml(options = {})
          builder = Oga::XML::Builder.new
          build_element(builder, @root, options)
          xml_data = builder.to_xml
          options[:declaration] ? declaration(options) + xml_data : xml_data
        end

        private

        def build_element(builder, element, options = {})
          attributes = build_attributes(element.attributes)
          builder.element(element.name, attributes) do
            element.children.each do |child|
              build_element(builder, child, options)
            end
            builder.text(element.text) if element.text
          end
        end

        def build_attributes(attributes)
          attributes.transform_values(&:value)
        end

        def parse_element(element)
          result = { "_text" => element.text }
          element.children.each do |child|
            next if child.is_a?(Oga::XML::Text)

            result[child.name] ||= []
            result[child.name] << parse_element(child)
          end
          result
        end
      end

      class OgaElement < XmlElement
        def initialize(node)
          attributes = node.attributes.each_with_object({}) do |attr, hash|
            hash[attr.name] = XmlAttribute.new(attr.name, attr.value)
          end
          super(node.name, attributes, parse_children(node), node.text)
        end

        private

        def parse_children(node)
          node.children.select do |child|
            child.is_a?(Oga::XML::Element)
          end.map { |child| OgaElement.new(child) }
        end
      end
    end
  end
end
