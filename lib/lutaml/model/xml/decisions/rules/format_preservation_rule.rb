# frozen_string_literal: true
# lib/lutaml/model/xml/decisions/rules/format_preservation_rule.rb
require_relative '../decision_rule'

module Lutaml
  module Model
    module Xml
      module Decisions
        module Rules
          # Priority 1: Preserve input format during round-trip
          #
          # When parsing XML, the input format is preserved and reused during
          # serialization to maintain format consistency
          class FormatPreservationRule < DecisionRule
            # Priority 1
            def priority
              1
            end

            # Applies when input format is preserved
            def applies?(context)
              return false unless context.has_namespace?
              !context.preserved_input_format.nil?
            end

            # Decision: Use the format from input
            def decide(context)
              input_format = context.preserved_input_format

              if input_format == :default
                Decision.default(
                  namespace_class: context.namespace_class,
                  reason: "Priority 1: Input used default format - preserve it"
                )
              else
                Decision.prefix(
                  prefix: context.namespace_class.prefix_default,
                  namespace_class: context.namespace_class,
                  reason: "Priority 1: Input used prefix format - preserve it"
                )
              end
            end
          end
        end
      end
    end
  end
end
