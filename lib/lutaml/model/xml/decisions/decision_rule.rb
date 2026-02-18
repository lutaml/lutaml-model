# frozen_string_literal: true

require_relative "decision"
require_relative "decision_context"

module Lutaml
  module Model
    module Xml
      module Decisions
        # Abstract base class for namespace decision rules
        #
        # Each rule encapsulates ONE decision criterion.
        # Rules are evaluated in priority order.
        # First rule that applies determines the decision.
        #
        # @abstract Subclass and implement {#applies?} and {#decide}
        class DecisionRule
          # Check if this rule applies to the given context
          #
          # @param context [DecisionContext] The decision context
          # @return [Boolean] true if this rule should be applied
          def applies?(context)
            raise NotImplementedError, "#{self.class} must implement #applies?"
          end

          # Make the decision for this rule
          #
          # @param context [DecisionContext] The decision context
          # @return [Decision] The decision
          def decide(context)
            raise NotImplementedError, "#{self.class} must implement #decide"
          end

          # Get the priority of this rule (lower = higher priority)
          #
          # @return [Integer] Priority (0-10)
          def priority
            raise NotImplementedError, "#{self.class} must implement #priority"
          end

          # Human-readable name of this rule
          #
          # @return [String]
          def name
            self.class.name.split("::").last
          end

          # Compare rules by priority (for sorting)
          #
          # @param other [DecisionRule] Another rule
          # @return [Integer] -1, 0, or 1
          def <=>(other)
            priority <=> other.priority
          end
        end
      end
    end
  end
end
