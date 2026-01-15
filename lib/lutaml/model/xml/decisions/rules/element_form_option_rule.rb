# frozen_string_literal: true

require_relative "../decision_rule"

module Lutaml
  module Model
    module Xml
      module Decisions
        module Rules
          # Decision rule for element form option from map_element
          #
          # When form: :qualified is specified on map_element, the element
          # MUST use prefix format to explicitly qualify the element name.
          # When form: :unqualified is specified, the element MUST NOT use
          # prefix format (uses default or blank namespace).
          #
          # Priority: 0.9 (between Tier 1 explicit option and Tier 2 format preservation)
          # - form: :qualified forces prefix format (even if preserved input used default)
          # - form: :unqualified forces default format (even if preserved input used prefix)
          #
          # This allows per-element qualification overrides of the namespace's
          # element_form_default setting.
          class ElementFormOptionRule < DecisionRule
            # @return [Integer] Priority level (-0.5 = higher than InheritFromParentRule's 0)
            def priority
              -0.5
            end

            # Check if rule applies
            #
            # @param context [DecisionContext] Decision context
            # @return [Boolean] true if element has form option set
            def applies?(context)
              return false unless context.element
              # Check if element responds to :form before accessing it
              return false unless context.element.respond_to?(:form)

              # Check if element has form attribute
              form = context.element.form
              !form.nil?
            end

            # Make the decision
            #
            # @param context [DecisionContext] Decision context
            # @return [Decision] The prefix decision
            def decide(context)
              form = context.element.form

              if form == :qualified
                # Force prefix format when form: :qualified
                # Use namespace's prefix_default if available
                prefix = context.namespace_class&.prefix_default

                if prefix
                  Decision.prefix(
                    prefix: prefix,
                    namespace_class: context.namespace_class,
                    reason: "Priority 0.9: form: :qualified forces prefix format"
                  )
                else
                  # No prefix available - this shouldn't happen in practice
                  # since form: :qualified implies the element has a namespace
                  Decision.new(
                    format: :default,
                    prefix: nil,
                    namespace_class: context.namespace_class,
                    reason: "Priority 0.9: form: :qualified but no namespace prefix available"
                  )
                end
              elsif form == :unqualified
                # Force default format when form: :unqualified
                Decision.default(
                  namespace_class: context.namespace_class,
                  reason: "Priority 0.9: form: :unqualified forces default format"
                )
              else
                # Unknown form value - should not happen
                Decision::NEUTRAL
              end
            end
          end
        end
      end
    end
  end
end
