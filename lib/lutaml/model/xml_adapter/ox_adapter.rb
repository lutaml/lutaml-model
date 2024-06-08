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

        def initialize(root)
          @root = root
        end

        def to_h
          { @root.name => parse_element(@root) }
        end

        def to_xml(options = {})
          builder = Ox::Builder.new
          build_element(builder, @root, options)
          xml_data = Ox.dump(builder)
          xml_data
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
          attributes.each_with_object({}) do |(name, attr), hash|
            hash[name] = attr.value
          end
        end

        def parse_element(element)
          result = { "_text" => element.text }
          element.nodes.each do |child|
            next if child.is_a?(Ox::Raw) || child.is_a?(Ox::Comment)
            result[child.name] ||= []
            result[child.name] << parse_element(child)
          end
          result
        end
      end

      class OxElement < Element
        def initialize(node)
          attributes = node.attributes.each_with_object({}) do |(name, value), hash|
            hash[name.to_s] = Attribute.new(name.to_s, value)
          end
          super(node.name.to_s,
                attributes,
                node.nodes.select { |child| child.is_a?(Ox::Element) }.map { |child| OxElement.new(child) },
                node.text)
        end
      end
    end
  end
end
