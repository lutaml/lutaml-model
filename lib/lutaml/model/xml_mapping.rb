# lib/lutaml/model/xml_mapping.rb
require_relative "xml_mapping_rule"

module Lutaml
  module Model
    class XmlMapping
      attr_reader :root_element, :namespace_uri, :namespace_prefix

      def initialize
        @elements = []
        @attributes = []
      end

      def root(name)
        @root_element = name
      end

      def namespace(uri, prefix = nil)
        @namespace_uri = uri
        @namespace_prefix = prefix
      end

      def map_element(name, to:, render_nil: false, with: {}, delegate: nil, namespace: nil, prefix: nil)
        @elements << XmlMappingRule.new(name, to: to, render_nil: render_nil, with: with, delegate: delegate, namespace: namespace, prefix: prefix)
      end

      def map_attribute(name, to:, render_nil: false, with: {}, delegate: nil, namespace: nil, prefix: nil)
        @attributes << XmlMappingRule.new(name, to: to, render_nil: render_nil, with: with, delegate: delegate, namespace: namespace, prefix: prefix)
      end

      def elements
        @elements
      end

      def attributes
        @attributes
      end

      def mappings
        elements + attributes
      end
    end
  end
end
