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
            build_element(xml, root, options)
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

        def build_element(xml, element, options = {})
          ns = element.namespace ? { element.namespace_prefix => element.namespace } : {}
          xml.send(element.name, build_attributes(element.attributes), ns) do
            element.children.each do |child|
              build_element(xml, child)
            end
            xml.text element.text if element.text
          end
        end

        def build_attributes(attributes)
          attributes.each_with_object({}) do |attr, hash|
            if attr.namespace
              hash["#{attr.namespace_prefix}:#{attr.name}"] = attr.value
            else
              hash[attr.name] = attr.value
            end
          end
        end
      end

      class NokogiriElement < Element
        attr_reader :namespace, :namespace_prefix

        def initialize(node)
          @namespace = node.namespace ? node.namespace.href : nil
          @namespace_prefix = node.namespace ? node.namespace.prefix : nil
          super(node.name, node.attributes.transform_values(&:value), node.children.map { |child| NokogiriElement.new(child) }, node.text)
        end
      end
    end
  end
end
