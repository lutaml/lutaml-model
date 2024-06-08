# lib/lutaml/model/xml_adapter/oga_adapter.rb
require "oga"
require_relative "../xml_adapter"

module Lutaml
  module Model
    module XmlAdapter
      class OgaDocument < Document
        def self.parse(xml)
          parsed = Oga.parse_xml(xml)
          root = OgaElement.new(parsed.root)
          new(root)
        end

        def to_xml(options = {})
          builder = Oga::XML::Builder.new do |xml|
            build_element(xml, root, options)
          end
          xml_data = builder.to_xml

          if options[:pretty]
            xml_data = Oga::XML::Document.new(xml_data).to_xml(indent: 2)
          end

          if options[:declaration]
            version = options[:declaration].is_a?(String) ? options[:declaration] : "1.0"
            encoding = options[:encoding].is_a?(String) ? options[:encoding] : (options[:encoding] ? "UTF-8" : nil)
            declaration = "<?xml version=\"#{version}\""
            declaration += " encoding=\"#{encoding}\"" if encoding
            declaration += "?>\n"
            xml_data = declaration + xml_data
          end

          xml_data
        end

        private

        def build_element(xml, element, options = {})
          attributes = build_attributes(element.attributes)
          if element.namespace
            attributes["xmlns:#{element.namespace_prefix}"] = element.namespace if element.namespace_prefix
            attributes["xmlns"] = element.namespace unless element.namespace_prefix
          end

          xml.send(element.name, attributes) do
            element.children.each do |child|
              build_element(xml, child)
            end
            xml.text element.text if element.text
          end
        end

        def build_attributes(attributes)
          attributes.each_with_object({}) do |attr, hash|
            if attr.namespace
              namespace_prefix = attr.namespace_prefix ? "#{attr.namespace_prefix}:" : ""
              name = "#{namespace_prefix}#{attr.name}"
            else
              name = attr.name
            end
            hash[name] = attr.value
          end
        end
      end

      class OgaElement < Element
        def initialize(node)
          attributes = node.attributes.transform_values do |attr|
            Attribute.new(attr.name, attr.value, namespace: attr.namespace&.uri, namespace_prefix: attr.namespace&.prefix)
          end
          super(node.name,
                attributes,
                node.children.select(&:element?).map { |child| OgaElement.new(child) },
                node.text,
                namespace: node.namespace&.uri,
                namespace_prefix: node.namespace&.prefix)
        end
      end
    end
  end
end
