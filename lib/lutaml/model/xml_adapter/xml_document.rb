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

        def handle_nested_elements(builder, value, rule: nil, attribute: nil)
          options = build_options_for_nested_elements(attribute, rule)

          case value
          when Array
            value.each { |val| build_element(builder, val, options) }
          else
            build_element(builder, value, options)
          end
        end

        def build_options_for_nested_elements(attribute, rule)
          return {} unless rule

          options = {}

          options[:namespace_prefix] = rule.prefix if rule&.namespace_set?
          options[:mixed_content] = rule.mixed_content

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

          if xml_mappings.namespace_prefix
            attrs["xmlns:#{xml_mappings.namespace_prefix}"] =
              xml_mappings.namespace_uri
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

        def build_attributes(element, xml_mapping)
          attrs = namespace_attributes(xml_mapping)

          xml_mapping.attributes.each_with_object(attrs) do |mapping_rule, hash|
            if mapping_rule.namespace
              hash["xmlns:#{mapping_rule.prefix}"] = mapping_rule.namespace
            end

            hash[mapping_rule.prefixed_name] = element.send(mapping_rule.to)
          end

          xml_mapping.elements.each_with_object(attrs) do |mapping_rule, hash|
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
