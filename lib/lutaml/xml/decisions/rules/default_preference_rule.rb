# frozen_string_literal: true

# lib/lutaml/model/xml/decisions/rules/default_preference_rule.rb
module Lutaml
  module Xml
    module Decisions
      module Rules
        # Priority 5: Default preference
        #
        # When no other rule applies:
        # - If namespace has element_form_default :unqualified, prefer prefix format
        #   (so children can be unqualified without xmlns="")
        # - Otherwise, prefer default namespace format (cleaner, no prefix)
        class DefaultPreferenceRule < DecisionRule
          # Priority 5 - Lowest priority (catch-all)
          def priority
            5
          end

          # Always applies (catch-all rule)
          def applies?(_context)
            # This rule always applies as the fallback
            true
          end

          # Decision: Prefer prefix format when element_form_default is unqualified
          # BUT: elementFormDefault only applies to LOCAL (nested) elements, not the root.
          # The root element itself should use default format.
          def decide(context)
            if context.has_namespace?
              ns_class = context.namespace_class
              # When element_form_default is EXPLICITLY set to unqualified AND this is NOT the root,
              # use prefix format so children can be in blank namespace (no xmlns).
              # Root element uses default format since elementFormDefault only affects local elements.
              # CRITICAL: Only applies when explicitly set, not when defaulted to :unqualified.
              if ns_class.element_form_default_set? &&
                  ns_class.element_form_default == :unqualified &&
                  !context.root?
                Decision.prefix(
                  prefix: ns_class.prefix_default || "ns",
                  namespace_class: ns_class,
                  reason: "Priority 5: element_form_default :unqualified (non-root) - use prefix for parent",
                )
              else
                Decision.default(
                  namespace_class: ns_class,
                  reason: "Priority 5: Default preference - use default format for cleaner output",
                )
              end
            else
              # No namespace - no decision needed
              Decision.default(
                namespace_class: nil,
                reason: "Priority 5: No namespace - no prefix needed",
              )
            end
          end
        end
      end
    end
  end
end
