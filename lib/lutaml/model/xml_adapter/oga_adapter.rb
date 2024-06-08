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
          doc = Oga::XML::Document.new
          root_element = build_element(root)
          doc.children << root_element
          xml_data = doc.to_xml
          xml_data = pretty_print(xml_data) if options[:pretty]

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

        def build_element(element)
          oga_element = Oga::XML::Element.new(element.name)
          element.attributes.each { |attr| oga_element.set(attr.name, attr.value) }

          element.children.each do |child|
            child_element = build_element(child)
            oga_element.children << child_element
          end

          oga_element.inner_text = element.text if element.text
          oga_element
        end

        def pretty_print(xml)
          doc = Oga.parse_xml(xml)
          doc.to_xml(encoding: "UTF-8", indent: 2)
        end
      end

      class OgaElement < Element
        def initialize(node)
          super(node.name, node.attributes.map { |attr| [attr.name, attr.value] }.to_h, node.children.map { |child| OgaElement.new(child) }, node.text)
        end
      end
    end
  end
end
