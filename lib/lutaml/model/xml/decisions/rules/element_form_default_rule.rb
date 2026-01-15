# frozen_string_literal: true
# lib/lutaml/model/xml/decisions/rules/element_form_default_rule.rb
require_relative '../decision_rule'

module Lutaml
  module Model
    module Xml
      module Decisions
        module Rules
          # REMOVED: Priority 4.5 rule that incorrectly forced prefix format
          #
          # PREVIOUS INCORRECT BEHAVIOR:
          # When namespace has element_form_default :qualified, this rule forced
          # prefix format based on incorrect interpretation of W3C XML Schema.
          #
          # CORRECT W3C SEMANTICS:
          # element_form_default :qualified means elements MUST be namespace-qualified
          # (in the target namespace, not blank namespace). It does NOT dictate whether
          # to use prefix format vs default format. Both are W3C compliant:
          #   - Prefix format: <xmi:Element xmlns:xmi="uri">
          #   - Default format: <Element xmlns="uri">
          #
          # The rule was disabled because:
          # 1. It violated format preservation (Tier 2 priority) by overriding input format
          # 2. It incorrectly interpreted W3C spec as requiring prefix format
          # 3. Format selection should respect priority order, not be forced by this setting
          #
          # Namespace-qualification is now enforced by other means (blank namespace handling).
          class ElementFormDefaultRule < DecisionRule
            # Priority 4.5 (between attribute usage and default preference)
            def priority
              4.5
            end

            # DISABLED: This rule no longer applies
            # element_form_default :qualified should only ensure namespace-qualification,
            # not force prefix format. Format selection respects priority order.
            def applies?(context)
              false
            end

            # Decision: N/A (rule disabled)
            def decide(context)
              # Should never be called since applies? always returns false
              Decision.default(
                namespace_class: context.namespace_class,
                reason: "Priority 4.5: Rule disabled - element_form_default does not force prefix format"
              )
            end
          end
        end
      end
    end
  end
end
