# frozen_string_literal: true
# lib/lutaml/model/xml/decisions/rules/explicit_option_rule.rb
require_relative '../decision_rule'

module Lutaml
  module Model
    module Xml
      module Decisions
        module Rules
          # Priority 0.75: Explicit prefix option
          #
          # User explicitly specified prefix option (true, false, or custom string)
          # CRITICAL: This MUST override FormatPreservationRule (Priority 1) to allow
          # users to override preserved input format during serialization.
          # Example: parse default, serialize prefixed (cross-parse)
          class ExplicitOptionRule < DecisionRule
            # Priority 0.75 - Higher than FormatPreservationRule (1)
            def priority
              0.75
            end

            # Applies when explicit prefix option is set
            def applies?(context)
              return false unless context.has_namespace?
              !context.explicit_prefix_option.nil?
            end

            # Decision: Use the explicit option value
            def decide(context)
              option = context.explicit_prefix_option

              if option.is_a?(String)
                # Custom prefix string
                Decision.prefix(
                  prefix: option,
                  namespace_class: context.namespace_class,
                  reason: "Priority 2: Explicit prefix option (custom string)"
                )
              elsif option == true
                # Force prefix format
                Decision.prefix(
                  prefix: context.namespace_class.prefix_default,
                  namespace_class: context.namespace_class,
                  reason: "Priority 2: Explicit prefix option (true)"
                )
              else
                # Force default format (option == false)
                Decision.default(
                  namespace_class: context.namespace_class,
                  reason: "Priority 2: Explicit prefix option (false)"
                )
              end
            end
          end
        end
      end
    end
  end
end
