# frozen_string_literal: true

module Lutaml
  module Xml
    class NokogiriElement < AdapterElement
      def initialize(node, parent: nil, default_namespace: nil)
        @raw_text = node.raw_content if node.is_a?(Moxml::Text)
        super
      end

      private

      def adapter_class
        Lutaml::Xml::Adapter::NokogiriAdapter
      end

      def build_text_for_xml
        @raw_text || @text
      end

      def build_element_xml(builder)
        builder.create_and_add_element(name,
                                       prefix: namespace_prefix,
                                       attributes: build_attributes(self)) do |xml|
          children.each { |child| child.build_xml(xml) }
        end
      end

      def attribute_value_for_build(attr)
        attr.raw_value
      end
    end
  end
end
