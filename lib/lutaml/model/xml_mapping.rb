require_relative "xml_mapping_rule"

module Lutaml
  module Model
    class XmlMapping
      attr_reader :root_element,
                  :namespace_uri,
                  :namespace_prefix,
                  :mixed_content

      def initialize
        @elements = {}
        @attributes = {}
        @content_mapping = nil
        @mixed_content = false
      end

      alias mixed_content? mixed_content

      def root(name, mixed: false)
        @root_element = name
        @mixed_content = mixed
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

      # rubocop:disable Metrics/ParameterLists
      def map_element(
        name,
        to: nil,
        render_nil: false,
        with: {},
        delegate: nil,
        namespace: (namespace_set = false
                    nil),
        prefix: nil
      )
        validate!(name, to, with)

        @elements[name] = XmlMappingRule.new(
          name,
          to: to,
          render_nil: render_nil,
          with: with,
          delegate: delegate,
          namespace: namespace,
          prefix: prefix,
          namespace_set: namespace_set != false,
        )
      end

      def map_attribute(
        name,
        to: nil,
        render_nil: false,
        with: {},
        delegate: nil,
        namespace: (namespace_set = false
                    nil),
        prefix: nil
      )
        validate!(name, to, with)

        @attributes[name] = XmlMappingRule.new(
          name,
          to: to,
          render_nil: render_nil,
          with: with,
          delegate: delegate,
          namespace: namespace,
          prefix: prefix,
          namespace_set: namespace_set != false,
        )
      end

      # rubocop:enable Metrics/ParameterLists

      def map_content(
        to: nil,
        render_nil: false,
        with: {},
        delegate: nil,
        mixed: false
      )
        validate!("content", to, with)

        @content_mapping = XmlMappingRule.new(
          nil,
          to: to,
          render_nil: render_nil,
          with: with,
          delegate: delegate,
          mixed_content: mixed,
        )
      end

      def validate!(key, to, with)
        if to.nil? && with.empty?
          msg = ":to or :with argument is required for mapping '#{key}'"
          raise IncorrectMappingArgumentsError.new(msg)
        end

        if !with.empty? && (with[:from].nil? || with[:to].nil?)
          msg = ":with argument for mapping '#{key}' requires :to and :from keys"
          raise IncorrectMappingArgumentsError.new(msg)
        end
      end

      def elements
        @elements.values
      end

      def attributes
        @attributes.values
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

      def find_by_name(name)
        if name.to_s == "text"
          content_mapping
        else
          mappings.detect do |rule|
            rule.name == name.to_s || rule.name == name.to_sym
          end
        end
      end
    end
  end
end
