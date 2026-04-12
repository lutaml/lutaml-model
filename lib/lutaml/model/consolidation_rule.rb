# frozen_string_literal: true

module Lutaml
  module Model
    # Base class for all rules within a ConsolidationMap.
    #
    # Subclasses define specific rule types:
    # - GatherRule: collect a shared attribute from grouped instances
    # - DispatchBlock: discriminator routing configuration
    # - PatternElementRule: map an element name to an attribute
    # - PatternContentRule: map text content to an attribute
    class ConsolidationRule
      # Marker base class for consolidation rules.
      # Subclasses: GatherRule, DispatchBlock, PatternElementRule, PatternContentRule

      # Base initialize - subclasses should call super
      def initialize(*_args); end

      private

      # Override in subclasses to provide rule-specific data
      def rule_data
        {}
      end
    end
  end
end
