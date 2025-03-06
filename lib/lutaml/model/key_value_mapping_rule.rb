require_relative "mapping_rule"

module Lutaml
  module Model
    class KeyValueMappingRule < MappingRule
      attr_reader :child_mappings,
                  :root_mappings

      def initialize(
        name,
        to:,
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
        super(
          name,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
          polymorphic: polymorphic,
          polymorphic_map: polymorphic_map,
          transform: transform,
          render_empty: render_empty,
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
          with: Utils.deep_dup(custom_methods),
          delegate: delegate,
          child_mappings: Utils.deep_dup(child_mappings),
          render_empty: render_empty.dup,
        )
      end

      def root_mapping?
        name == "root_mapping"
      end
    end
  end
end
