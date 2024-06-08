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
          attributes = build_attributes(element.attributes)
          if element.namespace
            attributes["xmlns:#{element.namespace_prefix}"] = element.namespace if element.namespace_prefix
            attributes["xmlns"] = element.namespace unless element.namespace_prefix
          end

          xml.send(element.name, attributes) do
            element.children.each do |child|
              build_element(xml, child)
            end
            xml.text element.text unless element.children.any?
          end
        end

        def build_attributes(attributes)
          attributes.each_with_object({}) do |(name, attr), hash|
            if attr.namespace
              namespace_prefix = attr.namespace_prefix ? "#{attr.namespace_prefix}:" : ""
              full_name = "#{namespace_prefix}#{name}"
            else
              full_name = name
            end
            hash[full_name] = attr.value
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
          super(node.name,
                attributes,
                node.children.select(&:element?).map { |child| NokogiriElement.new(child) },
                node.text,
                namespace: node.namespace&.href,
                namespace_prefix: node.namespace&.prefix)
        end

        def text?
          false
        end
      end
    end
  end
end
