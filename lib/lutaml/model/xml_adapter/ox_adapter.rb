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
          xml = Ox::Document.new(version: options[:declaration] || "1.0", encoding: options[:encoding] || "UTF-8")
          xml << Ox::Element.new(root.name).tap do |element|
            build_element(element, root, options)
          end
          Ox.dump(xml, indent: options[:pretty] ? 2 : -1)
        end

        private

        def build_element(xml, element, options = {})
          attributes = build_attributes(element.attributes)
          if element.namespace
            attributes["xmlns:#{element.namespace_prefix}"] = element.namespace if element.namespace_prefix
            attributes["xmlns"] = element.namespace unless element.namespace_prefix
          end

          xml.attributes = xml.attributes.merge(attributes)
          element.children.each do |child|
            child_element = Ox::Element.new(child.name)
            build_element(child_element, child, options)
            xml << child_element
          end
          xml << Ox::CData.new(element.text) if element.text
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

      class OxElement < Element
        def initialize(node)
          attributes = node.attributes.transform_values do |value|
            namespace = node.namespace ? node.namespace.href : nil
            namespace_prefix = node.namespace ? node.namespace.prefix : nil
            Attribute.new(node.name, value, namespace: namespace, namespace_prefix: namespace_prefix)
          end
          super(node.name,
                attributes,
                node.nodes.select { |child| child.is_a?(Ox::Element) }.map { |child| OxElement.new(child) },
                node.text,
                namespace: node.namespace&.href,
                namespace_prefix: node.namespace&.prefix)
        end
      end
    end
  end
end
