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

        def to_xml(options = {})
          builder = Nokogiri::XML::Builder.new do |xml|
            build_element(xml, root)
          end
          xml_data = builder.to_xml
          xml_data = Nokogiri::XML(xml_data).to_xml(indent: 2) if options[:pretty]

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

        def build_element(xml, element)
          xml.send(element.name, build_attributes(element.attributes)) do
            element.children.each do |child|
              build_element(xml, child)
            end
            xml.text element.text if element.text
          end
        end

        def build_attributes(attributes)
          attributes.map { |attr| [attr.name, attr.value] }.to_h
        end
      end

      class NokogiriElement < Element
        def initialize(node)
          super(node.name, node.attributes.transform_values(&:value), node.children.map { |child| NokogiriElement.new(child) }, node.text)
        end
      end
    end
  end
end
