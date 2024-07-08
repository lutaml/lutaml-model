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
          # @root = OxElement.new(ox_node) if ox_node
        end

        def to_h
          # { @root.name => parse_element(@root) }
          parse_element(@root)
        end

        def to_xml(options = {})
          builder = Ox::Builder.new
          build_element(builder, @root, options)
          # xml_data = Ox.dump(builder)
          xml_data = builder.to_s
          options[:declaration] ? declaration(options) + xml_data : xml_data
        end

        private

        def build_element(builder, element, _options = {})
          return element.to_xml(builder) if element.is_a?(Lutaml::Model::XmlAdapter::OxElement)

          xml_mapping = element.class.mappings_for(:xml)
          return xml unless xml_mapping

          attributes = build_attributes(element, xml_mapping)

          builder.element(xml_mapping.root_element, attributes) do |el|
            xml_mapping.elements.each do |element_rule|
              if element_rule.delegate
                attribute_def = element.send(element_rule.delegate).class.attributes[element_rule.to]
                value = element.send(element_rule.delegate).send(element_rule.to)
              else
                attribute_def = element.class.attributes[element_rule.to]
                value = element.send(element_rule.to)
              end

              val = if attribute_def.collection?
                      value
                    elsif value || element_rule.render_nil?
                      [value]
                    else
                      []
                    end

              val.each do |v|
                if attribute_def&.type&.<= Lutaml::Model::Serialize
                  handle_nested_elements(el, element_rule, v)
                else
                  builder.element(element_rule.name) do |el|
                    el.text(attribute_def.type.serialize(v)) if v
                  end
                end
              end
            end
            # if element.children.any?
            #   element.children.each do |child|
            #     build_element(el, child, options)
            #   end
            # elsif element.text
            #   el.text(element.text)
            # end
          end
        end

        def handle_nested_elements(builder, _element_rule, value)
          case value
          when Array
            value.each { |val| build_element(builder, val) }
          else
            build_element(builder, value)
          end
        end

        # def build_attributes(element, xml_mapping)
        #   element_attributes = element.class.attributes

        #   attrs = element_attributes.each_with_object({}) do |(name, attr), hash|
        #     hash[attr.name] = attr.value
        #   end

        #   element.namespaces.each do |prefix, namespace|
        #     attrs[namespace.attr_name] = namespace.uri
        #   end

        #   attrs
        # end

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
        def initialize(node, root_node: nil)
          attributes = node.attributes.each_with_object({}) do |(name, value), hash|
            if attribute_is_namespace?(name)
              if root_node
                root_node.add_namespace(Lutaml::Model::XmlNamespace.new(value,
                                                                        name))
              else
                add_namespace(Lutaml::Model::XmlNamespace.new(value, name))
              end
            else
              if root_node && (n = root_node.namespaces[name.to_s.split(":").first])
                namespace = n.uri
                prefix = n.prefix
              end

              hash[name.to_s] =
                Attribute.new(name.to_s, value, namespace: namespace,
                                                namespace_prefix: prefix)
            end
          end

          super(
            node.name.to_s,
            attributes,
            parse_children(node, root_node: root_node || self),
            node.text,
            parent_document: root_node
          )
        end

        def to_xml(builder = nil)
          builder ||= Ox::Builder.new
          attrs = build_attributes(self)

          builder.element(name, attrs) do |el|
            if children.any?
              children.each do |child|
                child.to_xml(el)
              end
            elsif text
              el.text(text)
            end
          end
        end

        def build_attributes(node)
          attrs = node.attributes.transform_values(&:value)

          node.own_namespaces.each_value do |namespace|
            attrs[namespace.attr_name] = namespace.uri
          end

          attrs
        end

        private

        def parse_children(node, root_node: nil)
          node.nodes.select do |child|
            child.is_a?(Ox::Element)
          end.map do |child|
            OxElement.new(child,
                          root_node: root_node)
          end
        end
      end
    end
  end
end
