# lib/lutaml/model/xml_adapter.rb

require_relative "xml_namespace"
require_relative "mapping_hash"

module Lutaml
  module Model
    module XmlAdapter
      class Document
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

        def handle_nested_elements(builder, value)
          case value
          when Array
            value.each { |val| build_element(builder, val) }
          else
            build_element(builder, value)
          end
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
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

          element.attributes.each do |name, attr|
            result[name] = attr.value
          end

          result
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        def build_element(xml, element, _options = {})
          if element.ordered?
            build_ordered_element(xml, element, _options)
          else
            build_unordered_element(xml, element, _options)
          end
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
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
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        def attribute_definition_for(element, rule)
          return element.class.attributes[rule.to] unless rule.delegate

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

      class Element
        attr_reader :attributes,
                    :children,
                    :text,
                    :namespace_prefix,
                    :parent_document

        # rubocop:disable Metrics/ParameterLists
        def initialize(
          name,
          attributes = {},
          children = [],
          text = nil,
          parent_document: nil,
          namespace_prefix: nil
        )
          @name = extract_name(name)
          @namespace_prefix = namespace_prefix || extract_namespace_prefix(name)
          @attributes = attributes # .map { |k, v| Attribute.new(k, v) }
          @children = children
          @text = text
          @parent_document = parent_document
        end
        # rubocop:enable Metrics/ParameterLists

        def name
          if namespace_prefix && namespaces[namespace_prefix]
            "#{namespace_prefix}:#{@name}"
          else
            @name
          end
        end

        def unprefixed_name
          @name
        end

        def document
          Document.new(self)
        end

        def namespaces
          @namespaces || @parent_document&.namespaces || {}
        end

        def own_namespaces
          @namespaces || {}
        end

        def namespace
          return default_namespace unless namespace_prefix

          namespaces[namespace_prefix]
        end

        def attribute_is_namespace?(name)
          name.to_s.start_with?("xmlns")
        end

        def add_namespace(namespace)
          @namespaces ||= {}
          @namespaces[namespace.prefix] = namespace
        end

        def default_namespace
          namespaces[nil] || @parent_document&.namespaces&.dig(nil)
        end

        def extract_name(name)
          n = name.to_s.split(":")
          return name if n.length <= 1

          n[1..].join(":")
        end

        def extract_namespace_prefix(name)
          n = name.to_s.split(":")
          return if n.length <= 1

          n.first
        end

        def order
          result = children.each_with_object([]) do |child, arr|
            arr << child.unprefixed_name
          end

          result
        end
      end

      class Attribute
        attr_reader :name, :value, :namespace, :namespace_prefix

        def initialize(name, value, namespace: nil, namespace_prefix: nil)
          @name = name
          @value = value
          @namespace = namespace
          @namespace_prefix = namespace_prefix
        end
      end
    end
  end
end
