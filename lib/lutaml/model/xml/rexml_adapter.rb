require "rexml/document"
require "moxml"
require "moxml/adapter/rexml"
require_relative "document"
require_relative "rexml/element"
require_relative "builder/rexml"

module Lutaml
  module Model
    module Xml
      class RexmlAdapter < Document
        TEXT_CLASSES = [Moxml::Text, Moxml::Cdata].freeze

        def self.parse(xml, options = {})
          parse_encoding = encoding(xml, options)
          xml = normalize_xml_for_rexml(xml)

          parsed = Moxml::Adapter::Rexml.parse(xml)
          root_element = parsed.root || parse_with_escaped_ampersands(xml)

          if root_element.nil?
            raise REXML::ParseException.new(
              "Malformed XML: Unable to parse the provided XML document. " \
              "The document structure is invalid or incomplete.",
            )
          end

          @root = Rexml::Element.new(root_element, target_encoding: parse_encoding)
          new(@root, parse_encoding)
        end

        def to_xml(options = {})
          builder_options = { encoding: determine_encoding(options) }

          builder = Builder::Rexml.build(builder_options) do |xml|
            if @root.is_a?(Rexml::Element)
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

          element.attributes.each_value do |attr|
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
          return nil if element.nil?

          case element
          when Moxml::Text
            "text"
          when Moxml::Cdata
            "#cdata-section"
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

        def self.normalize_xml_for_rexml(xml)
          return xml unless xml.is_a?(String) && xml.encoding.to_s != "UTF-8"

          xml.encode("UTF-8")
        end

        def self.parse_with_escaped_ampersands(xml)
          return nil unless xml.is_a?(String)

          escaped_xml = xml.gsub(/&(?![a-zA-Z]+;|#[0-9]+;|#x[0-9a-fA-F]+;)/, "&amp;")
          Moxml::Adapter::Rexml.parse(escaped_xml).root
        end

        private

        def determine_encoding(options)
          options[:encoding] ||
            options[:parse_encoding] ||
            @encoding ||
            "UTF-8"
        end

        def build_ordered_element(builder, element, options = {})
          mapper_class = determine_mapper_class(element, options)
          xml_mapping = mapper_class.mappings_for(:xml)
          return builder unless xml_mapping

          attributes = build_attributes(element, xml_mapping, options).compact
          prefix = determine_namespace_prefix(options, xml_mapping)
          prefixed_xml = builder.add_namespace_prefix(prefix)
          tag_name = options[:tag_name] || xml_mapping.root_element

          prefixed_xml.create_and_add_element(tag_name, attributes: attributes) do |el|
            process_element_order(el, element, xml_mapping, mapper_class, options)
          end
        end

        def process_element_order(builder, element, xml_mapping, mapper_class, options)
          index_hash = {}
          content = []

          element.element_order.each do |object|
            process_ordered_object(builder, element, object, xml_mapping, mapper_class,
                                   index_hash, content, options)
          end

          builder.add_text(builder, content.join)
        end

        def process_ordered_object(builder, element, object, xml_mapping, mapper_class,
                                    index_hash, content, options)
          curr_index = increment_object_index(index_hash, object)
          element_rule = xml_mapping.find_by_name(object.name, type: object.type)

          return if skip_element_rule?(element_rule, options)

          attribute_def = attribute_definition_for(element, element_rule, mapper_class: mapper_class)
          value = attribute_value_for(element, element_rule)

          return if skip_cdata_text?(element_rule, xml_mapping, object)

          handle_ordered_element_content(builder, element, element_rule, xml_mapping,
                                         attribute_def, value, curr_index, content, options, mapper_class)
        end

        def increment_object_index(index_hash, object)
          object_key = "#{object.name}-#{object.type}"
          index_hash[object_key] ||= -1
          index_hash[object_key] += 1
        end

        def skip_element_rule?(element_rule, options)
          element_rule.nil? || options[:except]&.include?(element_rule.to)
        end

        def skip_cdata_text?(element_rule, xml_mapping, object)
          element_rule == xml_mapping.content_mapping && element_rule.cdata && object.text?
        end

        def handle_ordered_element_content(builder, element, element_rule, xml_mapping,
                                            attribute_def, value, curr_index, content, options, mapper_class)
          if element_rule == xml_mapping.content_mapping
            handle_ordered_content_text(builder, element, element_rule, xml_mapping, curr_index, content)
          elsif !value.nil? || element_rule.render_nil?
            add_ordered_element_value(builder, element, attribute_def, value, curr_index,
                                      element_rule, options, mapper_class)
          end
        end

        def handle_ordered_content_text(builder, element, element_rule, xml_mapping, curr_index, content)
          text = xml_mapping.content_mapping.serialize(element)
          text = text[curr_index] if text.is_a?(Array)

          return builder.add_text(builder, text, cdata: element_rule.cdata) if element.mixed?

          content << text
        end

        def add_ordered_element_value(builder, element, attribute_def, value, curr_index,
                                       element_rule, options, mapper_class)
          value = value[curr_index] if attribute_def.collection?

          add_to_xml(builder, element, nil, value,
                     options.merge(attribute: attribute_def, rule: element_rule,
                                   mapper_class: mapper_class))
        end
      end
    end
  end
end
