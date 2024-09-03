require_relative "../mapping_hash"
require_relative "xml_element"
require_relative "xml_attribute"
require_relative "xml_namespace"

module Lutaml
  module Model
    module XmlAdapter
      class XmlDocument
        attr_reader :root

        def initialize(root)
          @root = root
        end

        def self.parse(xml)
          raise NotImplementedError, "Subclasses must implement `parse`."
        end

        def children
          @root.children
        end

        def declaration(options)
          version = "1.0"
          version = options[:declaration] if options[:declaration].is_a?(String)

          encoding = options[:encoding] ? "UTF-8" : nil
          encoding = options[:encoding] if options[:encoding].is_a?(String)

          declaration = "<?xml version=\"#{version}\""
          declaration += " encoding=\"#{encoding}\"" if encoding
          declaration += "?>\n"
          declaration
        end

        def to_h
          parse_element(@root)
        end

        def order
          @root.order
        end

        def handle_nested_elements(builder, value, options = {})
          element_options = build_options_for_nested_elements(options)

          case value
          when Array
            value.each { |val| build_element(builder, val, element_options) }
          else
            build_element(builder, value, element_options)
          end
        end

        def build_options_for_nested_elements(options = {})
          attribute = options.delete(:attribute)
          rule = options.delete(:rule)

          return {} unless rule

          # options = {}

          options[:namespace_prefix] = rule.prefix if rule&.namespace_set?
          options[:mixed_content] = rule.mixed_content
          options[:tag_name] = rule.name

          options[:mapper_class] = attribute&.type if attribute

          options
        end

        def parse_element(element)
          result = Lutaml::Model::MappingHash.new
          result.item_order = element.order

          element.children.each_with_object(result) do |child, hash|
            value = child.text? ? child.text : parse_element(child)

            if hash[child.unprefixed_name]
              hash[child.unprefixed_name] =
                [hash[child.unprefixed_name], value].flatten
            else
              hash[child.unprefixed_name] = value
            end
          end

          element.attributes.each_value do |attr|
            result[attr.unprefixed_name] = attr.value
          end

          result
        end

        def build_element(xml, element, options = {})
          if ordered?(element, options)
            build_ordered_element(xml, element, options)
          else
            build_unordered_element(xml, element, options)
          end
        end

        def add_to_xml(xml, prefix, value, options = {})
          if value.is_a?(Array)
            value.each do |item|
              add_to_xml(xml, prefix, item, options)
            end

            return
          end

          attribute = options[:attribute]
          rule = options[:rule]

          if rule.custom_methods[:to]
            @root.send(rule.custom_methods[:to], @root, xml.parent, xml)
            return
          end

          if value && (attribute&.type&.<= Lutaml::Model::Serialize)
            handle_nested_elements(
              xml,
              value,
              options.merge({ rule: rule, attribute: attribute }),
            )
          else
            xml.create_and_add_element(rule.name, prefix: prefix) do
              if !value.nil?
                serialized_value = attribute.type.serialize(value)

                if attribute.type == Lutaml::Model::Type::Hash
                  serialized_value.each do |key, val|
                    xml.create_and_add_element(key) do |element|
                      element.text(val)
                    end
                  end
                else
                  xml.add_text(xml, serialized_value)
                end
              end
            end
          end
        end

        def build_unordered_element(xml, element, options = {})
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml)
          return xml unless xml_mapping

          attributes = options[:xml_attributes] ||= {}
          attributes = build_attributes(element,
                                        xml_mapping, options).merge(attributes)&.compact

          prefix = if options.key?(:namespace_prefix)
                     options[:namespace_prefix]
                   elsif xml_mapping.namespace_prefix
                     xml_mapping.namespace_prefix
                   end

          prefixed_xml = xml.add_namespace_prefix(prefix)
          tag_name = options[:tag_name] || xml_mapping.root_element

          prefixed_xml.create_and_add_element(tag_name, prefix: prefix,
                                                        attributes: attributes) do
            if options.key?(:namespace_prefix) && !options[:namespace_prefix]
              prefixed_xml.add_namespace_prefix(nil)
            end

            xml_mapping.elements.each do |element_rule|
              attribute_def = attribute_definition_for(element, element_rule,
                                                       mapper_class: mapper_class)

              value = attribute_value_for(element, element_rule)

              next if value.nil? && !element_rule.render_nil?

              value = [value] if attribute_def.collection? && !value.is_a?(Array)

              add_to_xml(
                prefixed_xml,
                element_rule.prefix,
                value,
                options.merge({ attribute: attribute_def, rule: element_rule }),
              )
            end

            if (content_rule = xml_mapping.content_mapping)
              if content_rule.custom_methods[:to]
                @root.send(content_rule.custom_methods[:to], element,
                           prefixed_xml.parent, prefixed_xml)
              else
                text = element.send(content_rule.to)
                text = text.join if text.is_a?(Array)
                prefixed_xml.add_text(xml, text)
              end
            end
          end
        end

        def ordered?(element, options = {})
          return false unless element.respond_to?(:element_order)
          return element.ordered? if element.respond_to?(:ordered?)
          return options[:mixed_content] if options.key?(:mixed_content)

          mapper_class = options[:mapper_class]
          mapper_class ? mapper_class.mappings_for(:xml).mixed_content? : false
        end

        def build_namespace_attributes(klass, processed = {})
          xml_mappings = klass.mappings_for(:xml)
          attributes = klass.attributes

          attrs = {}

          if xml_mappings.namespace_uri
            prefixed_name = ["xmlns",
                             xml_mappings.namespace_prefix].compact.join(":")

            attrs[prefixed_name] = xml_mappings.namespace_uri
          end

          xml_mappings.mappings.each do |mapping_rule|
            processed[klass] ||= {}

            next if processed[klass][mapping_rule.name]

            processed[klass][mapping_rule.name] = true

            type = if mapping_rule.delegate
                     attributes[mapping_rule.delegate].type.attributes[mapping_rule.to].type
                   else
                     attributes[mapping_rule.to].type
                   end

            if type <= Lutaml::Model::Serialize
              attrs = attrs.merge(build_namespace_attributes(type, processed))
            end

            if mapping_rule.namespace
              attrs["xmlns:#{mapping_rule.prefix}"] = mapping_rule.namespace
            end
          end

          attrs
        end

        def build_attributes(element, xml_mapping, options = {})
          attrs = namespace_attributes(xml_mapping)

          xml_mapping.attributes.each_with_object(attrs) do |mapping_rule, hash|
            next if options[:except]&.include?(mapping_rule.to)

            if mapping_rule.namespace
              hash["xmlns:#{mapping_rule.prefix}"] = mapping_rule.namespace
            end

            hash[mapping_rule.prefixed_name] = element.send(mapping_rule.to)
          end

          xml_mapping.elements.each_with_object(attrs) do |mapping_rule, hash|
            next if options[:except]&.include?(mapping_rule.to)

            if mapping_rule.namespace
              hash["xmlns:#{mapping_rule.prefix}"] = mapping_rule.namespace
            end
          end
        end

        def attribute_definition_for(element, rule, mapper_class: nil)
          klass = mapper_class || element.class
          return klass.attributes[rule.to] unless rule.delegate

          element.send(rule.delegate).class.attributes[rule.to]
        end

        def attribute_value_for(element, rule)
          return element.send(rule.to) unless rule.delegate

          element.send(rule.delegate).send(rule.to)
        end

        def namespace_attributes(xml_mapping)
          return {} unless xml_mapping.namespace_uri

          key = ["xmlns", xml_mapping.namespace_prefix].compact.join(":")
          { key => xml_mapping.namespace_uri }
        end
      end
    end
  end
end
