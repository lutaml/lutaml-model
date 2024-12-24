require_relative "mapping_rule"

module Lutaml
  module Model
    class KeyValueMappingRule < MappingRule
      attr_reader :child_mappings

      def initialize(
        name,
        to:,
        render_nil: false,
        render_default: false,
        with: {},
        delegate: nil,
        child_mappings: nil,
        id: nil
      )
        super(
          name,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
          id: id
        )

        @child_mappings = child_mappings
      end

      def deep_dup
        self.class.new(
          name.dup,
          to: to.dup,
          render_nil: render_nil.dup,
          with: Utils.deep_dup(custom_methods),
          delegate: delegate,
          child_mappings: Utils.deep_dup(child_mappings),
        )
      end
    end
  end
end
