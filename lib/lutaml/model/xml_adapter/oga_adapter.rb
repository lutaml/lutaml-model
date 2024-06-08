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

        def to_xml(*args)
          doc = Oga::XML::Document.new
          root_element = build_element(root)
          doc.children << root_element
          doc.to_xml(*args)
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
      end

      class OgaElement < Element
        def initialize(node)
          super(node.name, node.attributes.map { |attr| [attr.name, attr.value] }.to_h, node.children.map { |child| OgaElement.new(child) }, node.text)
        end
      end
    end
  end
end
