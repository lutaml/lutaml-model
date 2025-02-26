require "oga"
require "moxml/adapter/oga"
require_relative "xml_document"
require_relative "oga/document"
require_relative "oga/element"
require_relative "builder/oga"

module Lutaml
  module Model
    module XmlAdapter
      class OgaAdapter < XmlDocument
        TEXT_CLASSES = [Moxml::Text, Moxml::Cdata].freeze

        def self.parse(xml, options = {})
          parsed = Moxml::Adapter::Oga.parse(xml)
          @root = Oga::Element.new(parsed.children.first)
          new(@root, encoding(xml, options))
        end

        def to_xml(options = {})
          builder_options = {}
          builder_options[:encoding] = if options.key?(:encoding)
                                         options[:encoding]
                                       elsif options.key?(:parse_encoding)
                                         options[:parse_encoding]
                                       else
                                         "UTF-8"
                                       end

          builder = Builder::Oga.build(builder_options) do |xml|
            if @root.is_a?(Oga::Element)
              @root.build_xml(xml)
            else
              build_element(xml, @root, options)
            end
          end
          xml_data = builder.to_xml
          options[:declaration] ? declaration(options) + xml_data : xml_data
        end

        def attributes_hash(element)
          result = Lutaml::Model::MappingHash.new

          element.attributes.each do |attr|
            if attr.name == "schemaLocation"
              result["__schema_location"] = {
                namespace: attr.namespace,
                prefix: attr.namespace.prefix,
                schema_location: attr.value,
              }
            else
              result[self.class.namespaced_attr_name(attr)] = attr.value
            end
          end

          result
        end

        def self.name_of(element)
          case element
          when Moxml::Text
            "text"
          when Moxml::Cdata
            "cdata"
          else
            element.name
          end
        end

        def self.prefixed_name_of(node)
          return name_of(node) if TEXT_CLASSES.include?(node.class)

          [node&.namespace&.prefix, node.name].compact.join(":")
        end

        def self.text_of(element)
          element.content
        end

        def self.namespaced_attr_name(attribute)
          attr_ns = attribute.namespace
          attr_name = attribute.name
          return attr_name unless attr_ns

          prefix = attr_name == "lang" ? attr_ns.prefix : attr_ns.uri
          [prefix, attr_name].compact.join(":")
        end

        def self.namespaced_name_of(node)
          return name_of(node) unless node.respond_to?(:namespace)

          [node&.namespace&.uri, node.name].compact.join(":")
        end

        def order
          children.map do |child|
            type = child.text? ? "Text" : "Element"
            Element.new(type, child.unprefixed_name)
          end
        end

        def self.order_of(element)
          element.children.map do |child|
            instance_args = if TEXT_CLASSES.include?(child.class)
                              ["Text", "text"]
                            else
                              ["Element", name_of(child)]
                            end
            Element.new(*instance_args)
          end
        end

        private

        def build_ordered_element(builder, element, options = {})
          mapper_class = determine_mapper_class(element, options)
          xml_mapping = mapper_class.mappings_for(:xml)
          return xml unless xml_mapping

          attributes = build_attributes(element, xml_mapping).compact

          tag_name = options[:tag_name] || xml_mapping.root_element
          builder.create_and_add_element(tag_name,
                                         attributes: attributes) do |el|
            index_hash = {}
            content = []

            element.element_order.each do |object|
              index_hash[object.name] ||= -1
              curr_index = index_hash[object.name] += 1

              element_rule = xml_mapping.find_by_name(object.name)
              next if element_rule.nil?

              attribute_def = attribute_definition_for(element, element_rule,
                                                       mapper_class: mapper_class)
              value = attribute_value_for(element, element_rule)

              next if element_rule == xml_mapping.content_mapping && element_rule.cdata && object.text?

              if element_rule == xml_mapping.content_mapping
                text = xml_mapping.content_mapping.serialize(element)
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
                    mapper_class: mapper_class,
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
