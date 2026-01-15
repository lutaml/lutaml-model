# frozen_string_literal: true
# lib/lutaml/model/xml/decisions/rules/inherit_from_parent_rule.rb
require_relative '../decision_rule'

module Lutaml
  module Model
    module Xml
      module Decisions
        module Rules
          # Priority 0: Inherit parent's default namespace
          #
          # When parent uses default format (xmlns="uri"), children in same namespace
          # should inherit by having NO prefix (not parent's prefix!)
          #
          # This handles two cases:
          # 1. Parent has explicit namespace_class in same namespace
          # 2. Parent has default namespace declared (child's namespace matches parent's default)
          class InheritFromParentRule < DecisionRule
            # Priority 0 - Highest priority
            def priority
              0
            end

            # Applies when:
            # - Parent uses default format
            # - Element is in same namespace as parent (explicit OR via default)
            def applies?(context)
              return false unless context.has_namespace?
              return false unless context.parent_uses_default_format?

              # Case 1: Both parent and child have explicit namespace_class in same namespace
              return true if context.same_namespace_as_parent?

              # Case 2: Parent has default namespace declared and child's namespace matches it
              context.namespace_matches_parent_default?
            end

            # Decision: Use default format to inherit
            def decide(context)
              Decision.default(
                namespace_class: context.namespace_class,
                reason: "Priority 0: Inherit parent's default namespace"
              )
            end
          end
        end
      end
    end
  end
end
