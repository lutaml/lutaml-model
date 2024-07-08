# lib/lutaml/model/xml_mapping.rb
require_relative "xml_mapping_rule"

module Lutaml
  module Model
    class XmlMapping
      attr_reader :root_element, :namespace_uri, :namespace_prefix

      def initialize
        @elements = []
        @attributes = []
        @content_mapping = nil
      end

      def root(name)
        @root_element = name
      end

      def prefixed_root
        if namespace_uri && namespace_prefix
          "#{namespace_prefix}:#{root_element}"
        else
          root_element
        end
      end

      def namespace(uri, prefix = nil)
        @namespace_uri = uri
        @namespace_prefix = prefix
      end

      def map_element(name, to:, render_nil: false, with: {}, delegate: nil,
namespace: nil, prefix: nil)
        @elements << XmlMappingRule.new(name, to: to, render_nil: render_nil,
                                              with: with, delegate: delegate, namespace: namespace, prefix: prefix)
      end

      def map_attribute(name, to:, render_nil: false, with: {}, delegate: nil,
namespace: nil, prefix: nil)
        @attributes << XmlMappingRule.new(name, to: to, render_nil: render_nil,
                                                with: with, delegate: delegate, namespace: namespace, prefix: prefix)
      end

      def map_content(to:, render_nil: false, with: {}, delegate: nil)
        @content_mapping = XmlMappingRule.new(nil, to: to,
                                                   render_nil: render_nil, with: with, delegate: delegate)
      end

      def elements
        @elements
      end

      def attributes
        @attributes
      end

      def content_mapping
        @content_mapping
      end

      def mappings
        elements + attributes + [content_mapping].compact
      end

      def element(name)
        elements.detect do |rule|
          name == rule.to
        end
      end

      def attribute(name)
        attributes.detect do |rule|
          name == rule.to
        end
      end
    end
  end
end
