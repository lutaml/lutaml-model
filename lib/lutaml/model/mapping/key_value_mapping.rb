require_relative "mapping"
require_relative "key_value_mapping_rule"

module Lutaml
  module Model
    class KeyValueMapping < Mapping
      attr_reader :format

      def initialize(format = nil)
        super()
        @mappings = {}
        @key_mapping = {}
        @value_mapping = {}
        @format = format
      end

      def root(name = nil)
        @root = name
      end

      def no_root
        @root = nil
      end

      def no_root?
        @root.nil?
      end

      def root_name
        @root
      end

      def map(
        name = nil,
        to: nil,
        render_nil: false,
        render_default: false,
        render_empty: false,
        treat_nil: nil,
        treat_empty: nil,
        treat_omitted: nil,
        with: {},
        delegate: nil,
        child_mappings: nil,
        root_mappings: nil,
        polymorphic: {},
        polymorphic_map: {},
        transform: {},
        value_map: {}
      )
        mapping_name = name_for_mapping(root_mappings, name)
        validate!(mapping_name, to, with, render_nil, render_empty)

        @mappings[mapping_name] = KeyValueMappingRule.new(
          mapping_name,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          render_empty: render_empty,
          treat_nil: treat_nil,
          treat_empty: treat_empty,
          treat_omitted: treat_omitted,
          with: with,
          delegate: delegate,
          child_mappings: child_mappings,
          root_mappings: root_mappings,
          polymorphic: polymorphic,
          polymorphic_map: polymorphic_map,
          transform: transform,
          value_map: value_map,
        )
      end

      alias map_element map

      def map_all(
        to: nil,
        render_nil: false,
        render_default: false,
        with: {},
        delegate: nil
      )
        @raw_mapping = true
        validate!(Constants::RAW_MAPPING_KEY, to, with, render_nil, nil)
        @mappings[Constants::RAW_MAPPING_KEY] = KeyValueMappingRule.new(
          Constants::RAW_MAPPING_KEY,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
        )
      end

      alias map_all_content map_all

      def map_instances(to:, polymorphic: {})
        @instance = to
        map(root_name || to, to: to, polymorphic: polymorphic)
        map_to_instance
      end

      def map_key(to_instance: nil, as_attribute: nil)
        @key_mapping = { "#{to_instance || as_attribute}": :key }
        map_to_instance
      end

      def map_value(to_instance: nil, as_attribute: nil)
        @value_mapping = { "#{to_instance || as_attribute}": :value }
        map_to_instance
      end

      def instance_mapping?
        @instance && (!@key_mapping.empty? || !@value_mapping.empty?)
      end

      def map_to_instance
        return if !instance_mapping?

        mapping_name = name_for_mapping(nil, root_name || @instance)
        @mappings[mapping_name].child_mappings = @key_mapping.merge(@value_mapping)
      end

      def name_for_mapping(root_mappings, name)
        return "root_mapping" if root_mappings

        name
      end

      def mappings
        @mappings.values
      end

      def mappings_hash
        @mappings
      end

      def validate!(key, to, with, render_nil, render_empty)
        validate_mappings!(key)
        validate_to_and_with_arguments!(key, to, with)

        # Validate `render_nil` for unsupported value
        validate_blank_mappings!(render_nil, render_empty)
        validate_root_mappings!(key)
      end

      def validate_to_and_with_arguments!(key, to, with)
        if to.nil? && with.empty? && !@raw_mapping
          raise IncorrectMappingArgumentsError.new(
            ":to or :with argument is required for mapping '#{key}'",
          )
        end

        validate_with_options!(to, key, with)
      end

      def validate_with_options!(to, key, with)
        return true if to

        if !with.empty? && (with[:from].nil? || with[:to].nil?) && !@raw_mapping
          raise IncorrectMappingArgumentsError.new(
            ":with argument for mapping '#{key}' requires :to and :from keys",
          )
        end
      end

      def validate_root_mappings!(name)
        if root_mapping || (name == "root_mapping" && @mappings.any?)
          raise MultipleMappingsError.new(
            "root_mappings cannot be used with other mappings",
          )
        end
      end

      def validate_blank_mappings!(render_nil, render_empty)
        if render_nil == :as_blank || render_empty == :as_blank
          raise IncorrectMappingArgumentsError.new(
            ":as_blank is not supported for key-value mappings",
          )
        end
      end

      def validate_mappings!(_type)
        if (@raw_mapping && Utils.present?(@mappings)) ||
            (!@raw_mapping && mappings.any?(&:raw_mapping?))
          raise StandardError, "map_all is not allowed with other mappings"
        end
      end

      def deep_dup
        self.class.new(@format).tap do |new_mapping|
          new_mapping.instance_variable_set(:@mappings, duplicate_mappings)
        end
      end

      def duplicate_mappings
        Utils.deep_dup(@mappings)
      end

      def find_by_to(to)
        mappings.find { |m| m.to.to_s == to.to_s }
      end

      def find_by_to!(to)
        mapping = find_by_to(to)

        return mapping if !!mapping

        raise Lutaml::Model::NoMappingFoundError.new(to.to_s)
      end

      def find_by_name(name)
        @mappings.find { |m| m.name.to_s == name.to_s }
      end

      def polymorphic_mapping
        mappings.find(&:polymorphic_mapping?)
      end

      def root_mapping
        mappings.find(&:root_mapping?)
      end

      Lutaml::Model::Config::KEY_VALUE_FORMATS.each do |format|
        define_method(:"format_#{format}?") do
          @format == format
        end
      end
    end
  end
end
