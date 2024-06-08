# lib/lutaml/model/xml_mapping.rb
module Lutaml
  module Model
    class XmlMapping
      attr_reader :root, :elements, :attributes

      def initialize
        @elements = []
        @attributes = []
      end

      def root(name)
        @root = name
      end

      def map_element(name, to:, render_nil: false, with: {})
        @elements << MappingRule.new(name, to: to, render_nil: render_nil, with: with)
      end

      def map_attribute(name, to:, render_nil: false, with: {})
        @attributes << MappingRule.new(name, to: to, render_nil: render_nil, with: with)
      end
    end
  end
end
