# frozen_string_literal: true

# lib/lutaml/model/xml/decisions/rules/element_form_default_rule.rb
require_relative "../decision_rule"

module Lutaml
  module Model
    module Xml
      module Decisions
        module Rules
          # Priority 4.5: Element form default qualified
          #
          # When namespace has element_form_default :qualified, elements should
          # be namespace-qualified. This can be achieved with either default format
          # (xmlns="...") or prefix format (xmlns:p="..." with p:element).
          #
          # RATIONALE:
          # - Both prefix format and default format are W3C compliant
          # - Default format is cleaner (no prefix needed)
          # - Prefer default format unless there's a specific reason to use prefix
          # - Prefix format is needed when multiple namespaces are involved
          #
          # IMPORTANT: This rule does NOT override input format preservation (Priority 1).
          # It only applies when no input format exists (programmatically created models).
          #
          # W3C COMPLIANCE:
          # elementFormDefault="qualified" means local elements must be namespace-qualified.
          # This can be satisfied by either:
          # 1. Default namespace: <element xmlns="http://example.com">
          # 2. Prefixed namespace: <p:element xmlns:p="http://example.com">
          class ElementFormDefaultRule < DecisionRule
            # Priority 4.5 (between attribute usage and default preference)
            def priority
              4.5
            end

            # Applies when:
            # 1. Element has a namespace
            # 2. Namespace has element_form_default :qualified
            # 3. No input format preserved (programmatic creation, not parsed XML)
            def applies?(context)
              return false unless context.has_namespace?

              ns_class = context.namespace_class
              return false unless ns_class

              # Check if namespace has element_form_default :qualified
              return false unless ns_class.respond_to?(:element_form_default)
              return false unless ns_class.element_form_default == :qualified

              # Only apply if no input format preserved (not from parsed XML)
              # If input format exists, FormatPreservationRule (Priority 1) handles it
              context.preserved_input_format.nil?
            end

            # Decision: Prefer default format (cleaner, no prefix)
            # The actual namespace qualification is handled by the namespace_class.
            # Default format is preferred for cleaner output.
            def decide(context)
              ns_class = context.namespace_class
              Decision.default(
                namespace_class: ns_class,
                reason: "Priority 4.5: element_form_default :qualified - prefer default format for cleaner output",
              )
            end
          end
        end
      end
    end
  end
end
