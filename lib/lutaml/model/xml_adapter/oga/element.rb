# frozen_string_literal: true

module Lutaml
  module Model
    module XmlAdapter
      module Oga
        class Element < XmlElement
          def initialize(node)
            name = if node.is_a?(::Oga::XML::Element)
                     node.name
                   elsif node.is_a?(::Oga::XML::Text)
                     "text"
                   end
            attributes = node.is_a?(::Oga::XML::Element) ? node_attributes(node) : {}
            children = node.is_a?(::Oga::XML::Element) ? parse_children(node) : []
            text = node.is_a?(::Oga::XML::Text) ? node.text : nil
            super(name, attributes, children, text)
          end

          def text?
            children.empty? && text&.length&.positive?
          end

          def text
            @text
          end

          def to_xml(builder = Builder::Oga.build)
            build_xml(builder).to_xml
          end

          def build_xml(builder = Builder::Oga.build)
            if name == "text"
              builder.add_text(builder.current_node, @text)
            else
              builder.create_element(name, build_attributes(builder)) do |xml|
                children.each { |child| child.build_xml(xml) }
              end
            end

            builder
          end

          def build_attributes(builder)
            attributes.each do |attr|
              builder.attribute(attr.name, attr.value)
            end
          end

          private

          def node_attributes(node)
            node.attributes.each_with_object({}) do |attr, hash|
              hash[attr.name] = XmlAttribute.new(attr.name, attr.value)
            end
          end

          def parse_children(node)
            node.children.map { |child| self.class.new(child) }
          end
        end
      end
    end
  end
end
