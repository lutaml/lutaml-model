require_relative "xml_mapping_rule"

module Lutaml
  module Model
    class XmlMapping
      include Lutaml::Model::Loggable

      TYPES = {
        attribute: :map_attribute,
        element: :map_element,
        content: :map_content,
        all_content: :map_all,
      }.freeze

      attr_reader :root_element,
                  :namespace_uri,
                  :namespace_prefix,
                  :mixed_content,
                  :ordered,
                  :element_sequence

      def initialize(format = :xml)
        @elements = {}
        @attributes = {}
        @element_sequence = []
        @content_mapping = nil
        @raw_mapping = nil
        @mixed_content = false
        @format = format
      end

      alias mixed_content? mixed_content
      alias ordered? ordered

      def root(name, mixed: false, ordered: false)
        @root_element = name
        @mixed_content = mixed
        @ordered = ordered || mixed # mixed contenet will always be ordered
      end

      def root?
        !!root_element
      end

      def no_root
        @no_root = true
      end

      def no_root?
        !!@no_root
      end

      def prefixed_root
        if namespace_uri && namespace_prefix
          "#{namespace_prefix}:#{root_element}"
        else
          root_element
        end
      end

      def namespace(uri, prefix = nil)
        raise Lutaml::Model::NoRootNamespaceError if no_root?

        @namespace_uri = uri
        @namespace_prefix = prefix
      end

      # rubocop:disable Metrics/ParameterLists
      def map_element(
        name,
        to: nil,
        render_nil: false,
        render_default: false,
        with: {},
        delegate: nil,
        cdata: false,
        polymorphic: {},
        namespace: (namespace_set = false
                    nil),
        prefix: (prefix_set = false
                 nil),
        transform: {},
        render_empty: false
      )
        validate!(name, to, with, render_nil, render_empty, type: TYPES[:element])

        rule = XmlMappingRule.new(
          name,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
          cdata: cdata,
          namespace: namespace,
          default_namespace: namespace_uri,
          prefix: prefix,
          polymorphic: polymorphic,
          namespace_set: namespace_set != false,
          prefix_set: prefix_set != false,
          transform: transform,
          render_empty: render_empty,
        )
        @elements[rule.namespaced_name] = rule
      end

      def map_attribute(
        name,
        to: nil,
        render_nil: false,
        render_default: false,
        with: {},
        delegate: nil,
        polymorphic_map: {},
        namespace: (namespace_set = false
                    nil),
        prefix: (prefix_set = false
                 nil),
        render_empty: false
      )
        validate!(name, to, with, render_nil, render_empty, type: TYPES[:attribute])
        warn_auto_handling(name) if name == "schemaLocation"

        rule = XmlMappingRule.new(
          name,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
          namespace: namespace,
          prefix: prefix,
          attribute: true,
          polymorphic_map: polymorphic_map,
          default_namespace: namespace_uri,
          namespace_set: namespace_set != false,
          prefix_set: prefix_set != false,
        )
        @attributes[rule.namespaced_name] = rule
      end

      # rubocop:enable Metrics/ParameterLists

      def map_content(
        to: nil,
        render_nil: false,
        render_default: false,
        with: {},
        delegate: nil,
        mixed: false,
        cdata: false,
        render_empty: false
      )
        validate!("content", to, with, render_nil, render_empty, type: TYPES[:content])

        @content_mapping = XmlMappingRule.new(
          nil,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
          mixed_content: mixed,
          cdata: cdata,
        )
      end

      def map_all(
        to:,
        render_nil: false,
        render_default: false,
        delegate: nil,
        with: {},
        namespace: (namespace_set = false
                    nil),
        prefix: (prefix_set = false
                 nil),
        render_empty: false
      )
        validate!(Constants::RAW_MAPPING_KEY, to, with, render_nil, render_empty, type: TYPES[:all_content])

        rule = XmlMappingRule.new(
          Constants::RAW_MAPPING_KEY,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
          namespace: namespace,
          prefix: prefix,
          default_namespace: namespace_uri,
          namespace_set: namespace_set != false,
          prefix_set: prefix_set != false,
        )

        @raw_mapping = rule
      end

      alias map_all_content map_all

      def sequence(&block)
        @element_sequence << Sequence.new(self).tap do |s|
          s.instance_eval(&block)
        end
      end

      def import_model_mappings(model)
        raise Lutaml::Model::ImportModelWithRootError.new(model) if model.root?

        mappings = model.mappings_for(:xml)
        @elements.merge!(mappings.instance_variable_get(:@elements))
        @attributes.merge!(mappings.instance_variable_get(:@attributes))
        (@element_sequence << mappings.element_sequence).flatten!
      end

      def validate!(key, to, with, render_nil, render_empty, type: nil)
        validate_mappings!(type)

        if to.nil? && with.empty?
          msg = ":to or :with argument is required for mapping '#{key}'"
          raise IncorrectMappingArgumentsError.new(msg)
        end

        if !with.empty? && (with[:from].nil? || with[:to].nil?)
          msg = ":with argument for mapping '#{key}' requires :to and :from keys"
          raise IncorrectMappingArgumentsError.new(msg)
        end

        if render_nil && render_empty && render_nil == render_empty
          raise IncorrectMappingArgumentsError.new(
            "render_empty and _render_nil cannot be set to the same value",
          )
        end

        if render_nil == :as_empty || render_empty == :as_empty
          raise IncorrectMappingArgumentsError.new(
            ":as_empty is not supported for XML mappings",
          )
        end
      end

      def validate_mappings!(type)
        if !@raw_mapping.nil? && type != TYPES[:attribute]
          raise StandardError, "#{type} is not allowed, only #{TYPES[:attribute]} " \
                               "is allowed with #{TYPES[:all_content]}"
        end

        if !(elements.empty? && content_mapping.nil?) && type == TYPES[:all_content]
          raise StandardError, "#{TYPES[:all_content]} is not allowed with other mappings"
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

      def raw_mapping
        @raw_mapping
      end

      def mappings
        elements + attributes + [content_mapping, raw_mapping].compact
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
        if ["text", "#cdata-section"].include?(name.to_s)
          content_mapping
        else
          mappings.detect do |rule|
            rule.name == name.to_s || rule.name == name.to_sym
          end
        end
      end

      def deep_dup
        self.class.new.tap do |xml_mapping|
          xml_mapping.root(@root_element.dup, mixed: @mixed_content,
                                              ordered: @ordered)
          xml_mapping.namespace(@namespace_uri.dup, @namespace_prefix.dup)

          attributes_to_dup.each do |var_name|
            value = instance_variable_get(var_name)
            xml_mapping.instance_variable_set(var_name, Utils.deep_dup(value))
          end
        end
      end

      def polymorphic_mapping
        mappings.find(&:polymorphic_mapping?)
      end

      def attributes_to_dup
        @attributes_to_dup ||= %i[
          @content_mapping
          @raw_mapping
          @element_sequence
          @attributes
          @elements
        ]
      end

      def dup_mappings(mappings)
        new_mappings = {}

        mappings.each do |key, mapping_rule|
          new_mappings[key] = mapping_rule.deep_dup
        end

        new_mappings
      end
    end
  end
end
