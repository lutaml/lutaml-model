require_relative "key_value_mapping_rule"

module Lutaml
  module Model
    class KeyValueMapping
      attr_reader :mappings, :format

      def initialize(format = nil)
        @mappings = []
        @format = format
      end

      def map(
        name = nil,
        to: nil,
        render_nil: false,
        render_default: false,
        with: {},
        delegate: nil,
        child_mappings: nil,
        root_mappings: nil,
        polymorphic: {},
        polymorphic_map: {},
        transform: {},
        render_empty: false
      )
        mapping_name = name_for_mapping(root_mappings, name)
        validate!(mapping_name, to, with, render_nil, render_empty)

        @mappings << KeyValueMappingRule.new(
          mapping_name,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
          child_mappings: child_mappings,
          root_mappings: root_mappings,
          polymorphic: polymorphic,
          polymorphic_map: polymorphic_map,
          transform: transform,
          render_empty: render_empty,
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
        @mappings << KeyValueMappingRule.new(
          Constants::RAW_MAPPING_KEY,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
        )
      end

      alias map_all_content map_all

      def name_for_mapping(root_mappings, name)
        return "root_mapping" if root_mappings

        name
      end

      def validate!(key, to, with, render_nil, render_empty)
        validate_mappings!(key)

        if to.nil? && with.empty? && !@raw_mapping
          raise IncorrectMappingArgumentsError.new(
            ":to or :with argument is required for mapping '#{key}'",
          )
        end

        if !with.empty? && (with[:from].nil? || with[:to].nil?) && !@raw_mapping
          raise IncorrectMappingArgumentsError.new(
            ":with argument for mapping '#{key}' requires :to and :from keys",
          )
        end

        { render_nil: render_nil, render_empty: render_empty }.each do |option, value|
          if format_toml? && value == :as_nil
            raise IncorrectMappingArgumentsError.new(
              ":toml format does not support #{option}: #{value} mode",
            )
          end
        end

        if render_nil && render_empty && render_nil == render_empty
          raise IncorrectMappingArgumentsError.new(
            "render_empty and _render_nil cannot be set to the same value",
          )
        end

        # Validate `render_nil` for unsupported value
        if render_nil == :as_blank || render_empty == :as_blank
          raise IncorrectMappingArgumentsError.new(
            ":as_blank is not supported for key-value mappings",
          )
        end

        validate_mappings(key)
      end

      def validate_mappings(name)
        if @mappings.any?(&:root_mapping?) || (name == "root_mapping" && @mappings.any?)
          raise MultipleMappingsError.new("root_mappings cannot be used with other mappings")
        end
      end

      def validate_mappings!(_type)
        if (@raw_mapping && Utils.present?(@mappings)) || (!@raw_mapping && @mappings.any?(&:raw_mapping?))
          raise StandardError, "map_all is not allowed with other mappings"
        end
      end

      def deep_dup
        self.class.new.tap do |new_mapping|
          new_mapping.instance_variable_set(:@mappings, duplicate_mappings)
        end
      end

      def duplicate_mappings
        @mappings.map(&:deep_dup)
      end

      def find_by_to(to)
        @mappings.find { |m| m.to.to_s == to.to_s }
      end

      def polymorphic_mapping
        @mappings.find(&:polymorphic_mapping?)
      end

      Lutaml::Model::Config::KEY_VALUE_FORMATS.each do |format|
        define_method(:"format_#{format}?") do
          @format == format
        end
      end
    end
  end
end
