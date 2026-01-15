# frozen_string_literal: true
# lib/lutaml/model/xml/decisions/rules/default_preference_rule.rb
require_relative '../decision_rule'

module Lutaml
  module Model
    module Xml
      module Decisions
        module Rules
          # Priority 5: Default preference
          #
          # When no other rule applies, prefer default namespace format
          # (cleaner, no prefix, follows W3C minimal-subtree principle)
          class DefaultPreferenceRule < DecisionRule
            # Priority 5 - Lowest priority (catch-all)
            def priority
              5
            end

            # Always applies (catch-all rule)
            def applies?(context)
              # This rule always applies as the fallback
              true
            end

            # Decision: Use default format (cleaner, no prefix)
            def decide(context)
              if context.has_namespace?
                Decision.default(
                  namespace_class: context.namespace_class,
                  reason: "Priority 5: Default preference - use default format for cleaner output"
                )
              else
                # No namespace - no decision needed
                Decision.default(
                  namespace_class: nil,
                  reason: "Priority 5: No namespace - no prefix needed"
                )
              end
            end
          end
        end
      end
    end
  end
end
