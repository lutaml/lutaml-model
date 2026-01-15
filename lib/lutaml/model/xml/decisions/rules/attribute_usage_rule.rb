# frozen_string_literal: true
# lib/lutaml/model/xml/decisions/rules/attribute_usage_rule.rb
require_relative '../decision_rule'

module Lutaml
  module Model
    module Xml
      module Decisions
        module Rules
          # Priority 4: W3C rule - namespace used in attributes
          #
          # Namespaces used in attributes REQUIRE prefix format (W3C constraint:
          # only one default namespace per element)
          class AttributeUsageRule < DecisionRule
            # Priority 4
            def priority
              4
            end

            # Applies when namespace is used in attributes
            def applies?(context)
              return false unless context.has_namespace?
              context.used_in_attributes?
            end

            # Decision: MUST use prefix format (W3C rule)
            def decide(context)
              Decision.prefix(
                prefix: context.namespace_class.prefix_default,
                namespace_class: context.namespace_class,
                reason: "Priority 4: W3C rule - namespace used in attributes requires prefix"
              )
            end
          end
        end
      end
    end
  end
end
