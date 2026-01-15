# frozen_string_literal: true

# lib/lutaml/model/xml/decisions/decision_engine.rb
require_relative 'decision'
require_relative 'decision_context'
require_relative 'decision_rule'

module Lutaml
  module Model
    module Xml
      module Decisions
        # Decision Engine - Evaluates rules in priority order
        #
        # Uses Chain of Responsibility pattern to evaluate rules from highest
        # to lowest priority. First rule that applies determines the decision.
        class DecisionEngine
          attr_reader :rules

          def initialize(rules = [])
            @rules = rules.sort # Sort by priority (lower = higher priority)
            freeze
          end

          # Evaluate all rules and return the first applicable decision
          #
          # @param context [DecisionContext] The decision context
          # @return [Decision] The decision made by the first applicable rule
          # @raise [RuntimeError] If no rule applies (should never happen)
          def execute(context)
            @rules.each do |rule|
              if rule.applies?(context)
                return rule.decide(context)
              end
            end

            # This should never happen if DefaultPreferenceRule is included
            raise RuntimeError, "No decision rule applied for context: #{context.inspect}"
          end

          # Add a rule to the engine
          #
          # @param rule [DecisionRule] The rule to add
          # @return [DecisionEngine] A new engine with the rule added
          def add_rule(rule)
            new_rules = @rules + [rule]
            DecisionEngine.new(new_rules)
          end

          # Create a default engine with all standard rules
          #
          # @return [DecisionEngine] An engine with all priority rules
          def self.default
            require_relative 'rules'
            rules = [
              Rules::InheritFromParentRule.new,
              Rules::HoistedOnParentRule.new,
              Rules::FormatPreservationRule.new,
              Rules::ExplicitOptionRule.new,
              Rules::NamespaceScopeRule.new,
              Rules::AttributeUsageRule.new,
              Rules::ElementFormDefaultRule.new,
              Rules::DefaultPreferenceRule.new, # Must be last (catch-all)
            ]
            new(rules)
          end
        end
      end
    end
  end
end
