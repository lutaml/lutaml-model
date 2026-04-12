# frozen_string_literal: true

module Lutaml
  module Model
    class ConsolidationMap
      attr_reader :by, :to, :group_class, :rules

      # @param by [Symbol] grouping criterion (:attr_name or :pattern)
      # @param to [Symbol] target attribute name on Collection
      # @param group_class [Class] resolved from Collection's Organization
      # @param rules [Array<ConsolidationRule>] consolidation rules
      def initialize(by:, to:, group_class:, rules:)
        @by = by
        @to = to
        @group_class = group_class
        @rules = rules
      end

      def pattern?
        @by == :pattern
      end

      def attribute_based?
        !pattern?
      end

      # Builder evaluates the consolidate_map block
      class Builder
        def initialize(by, to, group_class)
          @by = by
          @to = to
          @group_class = group_class
          @rules = []
        end

        # Pattern A: gather a shared attribute from grouped instances
        def gather(source, to:)
          @rules << GatherRule.new(source, to)
        end

        # Pattern A: declare discriminator routing
        def dispatch_by(discriminator, &)
          routes = DispatchBuilder.new.evaluate(&)
          @rules << DispatchBlock.new(discriminator, routes)
        end

        # Pattern B: map an element name to an attribute
        def map_element(element_name, to:)
          @rules << PatternElementRule.new(element_name, to)
        end

        # Pattern B: map text content to an attribute
        def map_content(to:)
          @rules << PatternContentRule.new(to)
        end

        def build
          ConsolidationMap.new(
            by: @by,
            to: @to,
            group_class: @group_class,
            rules: @rules,
          )
        end
      end
    end
  end
end
