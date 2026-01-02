require_relative "mapping_rule"

module Lutaml
  module Model
    class KeyValueMappingRule < MappingRule
      attr_accessor :child_mappings,
                    :root_mappings

      def initialize(
        name,
        to:,
        to_instance: nil,
        as_attribute: nil,
        render_nil: false,
        render_default: false,
        render_empty: false,
        treat_nil: :nil,
        treat_empty: :empty,
        treat_omitted: :nil,
        with: {},
        delegate: nil,
        child_mappings: nil,
        root_mappings: nil,
        polymorphic: {},
        polymorphic_map: {},
        transform: {},
        value_map: {}
      )
        super(
          name,
          to: to,
          to_instance: to_instance,
          as_attribute: as_attribute,
          render_nil: render_nil,
          render_default: render_default,
          render_empty: render_empty,
          treat_nil: treat_nil,
          treat_empty: treat_empty,
          treat_omitted: treat_omitted,
          with: with,
          delegate: delegate,
          polymorphic: polymorphic,
          polymorphic_map: polymorphic_map,
          transform: transform,
          value_map: value_map,
        )

        @child_mappings = child_mappings
        @root_mappings = root_mappings
      end

      def hash_mappings
        return @root_mappings if @root_mappings

        @child_mappings
      end

      def deep_dup
        self.class.new(
          name.dup,
          to: to.dup,
          render_nil: render_nil.dup,
          render_default: render_default.dup,
          render_empty: render_empty.dup,
          with: Utils.deep_dup(custom_methods),
          delegate: delegate,
          child_mappings: Utils.deep_dup(child_mappings),
          root_mappings: Utils.deep_dup(root_mappings),
          value_map: Utils.deep_dup(@value_map),
        )
      end

      def root_mapping?
        name == "root_mapping"
      end
    end
  end
end
