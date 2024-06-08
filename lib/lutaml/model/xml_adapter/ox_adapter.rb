# lib/lutaml/model/xml_adapter/ox_adapter.rb
require "ox"
require_relative "../xml_adapter"

module Lutaml
  module Model
    module XmlAdapter
      class OxDocument < Document
        def self.parse(xml)
          parsed = Ox.parse(xml)
          root = OxElement.new(parsed)
          new(root)
        end

        def to_xml(options = {})
          ox_element = build_element(root)
          xml_data = Ox.dump(ox_element, indent: options[:pretty] ? 2 : -1)

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
          ox_element = Ox::Element.new(element.name)
          element.attributes.each { |attr| ox_element[attr.name] = attr.value }

          element.children.each do |child|
            child_element = build_element(child)
            child_element << child.text if child.text
            ox_element << child_element
          end

          ox_element
        end
      end

      class OxElement < Element
        def initialize(node)
          super(node.value, node.attributes || {}, node.nodes.map { |child| OxElement.new(child) }, node.text)
        end
      end
    end
  end
end
