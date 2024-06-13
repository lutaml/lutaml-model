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

          xml_data = if options[:pretty]
              builder.to_xml(indent: 2)
            else
              builder.to_xml
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
          xml_mapping = element.class.mappings_for(:xml)
          return xml unless xml_mapping

          attributes = build_attributes(element, xml_mapping)

          if xml_mapping.namespace_uri
            if xml_mapping.namespace_prefix
              attributes["xmlns:#{xml_mapping.namespace_prefix}"] = xml_mapping.namespace_uri
            else
              attributes["xmlns"] = xml_mapping.namespace_uri
            end
          end

          xml.send(xml_mapping.root_element, attributes) do
            xml_mapping.elements.each do |element_rule|
              attribute_def = element.class.attributes[element_rule.to]
              value = element.send(element_rule.to)

              puts "_" * 30
              pp element_rule
              pp element.class.attributes
              pp value
              pp attribute_def
              pp attribute_def.type
              puts "_" * 30

              puts "is attribute_def.type a Serialize(#{attribute_def.type.is_a?(Lutaml::Model::Serialize)})? Serializable? (#{attribute_def.type.is_a?(Lutaml::Model::Serializable)})"

              pp attribute_def.type.ancestors

              if attribute_def && attribute_def.type <= Lutaml::Model::Serialize
                case value
                when Array
                  puts "case 1: XML serialize as an array of Serialize objects! #{element_rule.name}"
                  xml.send(element_rule.name) do
                    value.each do |val|
                      build_element(xml, val)
                    end
                  end
                else
                  puts "case 2: XML serialize as a single Serialize object! #{element_rule.name}"
                  xml.send(element_rule.name) do
                    build_element(xml, value)
                  end
                end
              else
                puts "case 3: XML serialize as a non-Serialize object! #{element_rule.name}"
                xml.send(element_rule.name) do
                  xml.text value
                end
              end
            end

            unless xml_mapping.elements.any?
              puts "case 4: writing text... #{element_rule.name}"
              xml.text element.text
            end
          end
        end

        def build_attributes(element, xml_mapping)
          xml_mapping.attributes.each_with_object({}) do |mapping_rule, hash|
            if mapping_rule
              if mapping_rule.namespace
                namespace_prefix = mapping_rule.prefix ? "#{mapping_rule.prefix}:" : ""
                full_name = "#{namespace_prefix}#{mapping_rule.name}"
              else
                full_name = mapping_rule.name
              end
              hash[full_name] = element.send(mapping_rule.to)
            end
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
