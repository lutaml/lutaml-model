require "oga"
require_relative "xml_document"
require_relative "oga/document"
require_relative "oga/element"
require_relative "builder/oga"

module Lutaml
  module Model
    module XmlAdapter
      class OgaAdapter < XmlDocument
        def self.parse(xml, options = {})
          options[:encoding] ||= xml.encoding
          xml.encode("UTF-16").encode!("UTF-8") if options[:encoding] && options[:encoding] != "UTF-8"
          parsed = ::Oga.parse_xml(xml)
          @root = Oga::Element.new(parsed.children.first)
          new(@root, options[:encoding])
        end

        def to_xml(options = {})
          options[:to_encoding] = if options.key?(:encoding)
                                    options[:encoding]
                                  elsif self.encoding
                                    self.encoding
                                  else
                                    "UTF-8"
                                  end
          builder = Builder::Oga.build(options) do |builder|
            build_element(builder, @root, options)
          end
          builder.document.children.last.children << ::Oga::XML::Text.new(text: "\n")
          xml_data = builder.to_xml.encode!(options[:to_encoding])
          options[:declaration] ? declaration(options) + xml_data : xml_data
        end

        private

        def build_ordered_element(builder, element, options = {})
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml)
          return xml unless xml_mapping

          attributes = build_attributes(element, xml_mapping).compact

          tag_name = options[:tag_name] || xml_mapping.root_element
          builder.create_and_add_element(tag_name,
                                         attributes: attributes) do |el|
            index_hash = {}
            content = []

            element.element_order.each do |name|
              index_hash[name] ||= -1
              curr_index = index_hash[name] += 1

              element_rule = xml_mapping.find_by_name(name)
              next if element_rule.nil?

              attribute_def = attribute_definition_for(element, element_rule,
                                                       mapper_class: mapper_class)
              value = attribute_value_for(element, element_rule)

              next if element_rule == xml_mapping.content_mapping && element_rule.cdata && name == "text"

              if element_rule == xml_mapping.content_mapping
                text = element.send(xml_mapping.content_mapping.to)
                text = text[curr_index] if text.is_a?(Array)

                next el.add_text(el, text, cdata: element_rule.cdata) if element.mixed?

                content << text
              elsif !value.nil? || element_rule.render_nil?
                value = value[curr_index] if attribute_def.collection?

                add_to_xml(
                  el,
                  element,
                  nil,
                  value,
                  options.merge(
                    attribute: attribute_def,
                    rule: element_rule,
                  ),
                )
              end
            end

            el.add_text(el, content.join)
          end
        end
      end
    end
  end
end
