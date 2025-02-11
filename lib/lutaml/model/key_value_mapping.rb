require_relative "key_value_mapping_rule"

module Lutaml
  module Model
    class KeyValueMapping
      attr_reader :key_value_mappings

      def initialize
        @key_value_mappings = {}
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
        transform: {}
      )
        mapping_name = name_for_mapping(root_mappings, name)
        validate!(mapping_name, to, with)

        @key_value_mappings[mapping_name] = KeyValueMappingRule.new(
          mapping_name,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
          child_mappings: child_mappings,
          root_mappings: root_mappings,
          transform: transform,
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
        validate!(Constants::RAW_MAPPING_KEY, to, with)
        @key_value_mappings["map_all"] = KeyValueMappingRule.new(
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

      def import_model_mappings(model)
        raise Lutaml::Model::ImportModelWithRootError.new(model) if model.mappings.key?(:xml) && model.root?

        current_format = self.class.instance_variable_get(:@current_mapping_format)
        formats_to_import = current_format.is_a?(Array) ? current_format : [current_format]

        formats_to_import.each do |format|
          @key_value_mappings.merge!(model.mappings_for(format).key_value_mappings)
        end
      end

      def validate!(key, to, with)
        validate_mappings!(key)

        if to.nil? && with.empty? && !@raw_mapping
          msg = ":to or :with argument is required for mapping '#{key}'"
          raise IncorrectMappingArgumentsError.new(msg)
        end

        if !with.empty? && (with[:from].nil? || with[:to].nil?) && !@raw_mapping
          msg = ":with argument for mapping '#{key}' requires :to and :from keys"
          raise IncorrectMappingArgumentsError.new(msg)
        end

        validate_mappings(key)
      end

      def validate_mappings(name)
        if @key_value_mappings.values.any?(&:root_mapping?) || (name == "root_mapping" && @key_value_mappings.any?)
          raise MultipleMappingsError.new("root_mappings cannot be used with other mappings")
        end
      end

      def validate_mappings!(_type)
        if (@raw_mapping && Utils.present?(@key_value_mappings)) || (!@raw_mapping && @key_value_mappings.values.any?(&:raw_mapping?))
          raise StandardError, "map_all is not allowed with other mappings"
        end
      end

      def mappings
        @key_value_mappings.values
      end

      def deep_dup
        self.class.new.tap do |new_mapping|
          new_mapping.instance_variable_set(:@key_value_mappings, duplicate_mappings)
        end
      end

      def duplicate_mappings
        @key_value_mappings.transform_values(&:deep_dup)
      end

      def find_by_to(to)
        mappings.find { |m| m.to.to_s == to.to_s }
      end
    end
  end
end
