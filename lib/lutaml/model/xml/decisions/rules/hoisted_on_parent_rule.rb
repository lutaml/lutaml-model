# frozen_string_literal: true
# lib/lutaml/model/xml/decisions/rules/hoisted_on_parent_rule.rb
require_relative '../decision_rule'

module Lutaml
  module Model
    module Xml
      module Decisions
        module Rules
          # Priority 0.5: Namespace was hoisted on parent
          #
          # When parent declared a namespace (as prefix OR default), children in that
          # namespace MUST use the same format. If parent used default format (xmlns="uri"),
          # children inherit with NO prefix. If parent used prefix format (xmlns:p="uri"),
          # children use the same prefix.
          class HoistedOnParentRule < DecisionRule
            # Priority 0.5 - Second highest
            def priority
              0.5
            end

            # Applies when namespace is hoisted on parent
            def applies?(context)
              return false unless context.has_namespace?
              # Only apply if this element's namespace matches the parent's default namespace
              # If element has a different namespace than parent's default, it should
              # use its own namespace declaration (not inherit from parent's hoisted namespace)
              context.hoisted_on_parent? && context.namespace_matches_parent_default?
            end

            # Decision: Use the same format as parent (prefix or default)
            def decide(context)
              prefix = context.hoisted_prefix_on_parent

              # CRITICAL: If parent hoisted as default (prefix=nil), child must inherit
              # with default format (no prefix). If parent hoisted as prefix, child uses
              # that same prefix.
              if prefix.nil?
                Decision.default(
                  namespace_class: context.namespace_class,
                  reason: "Priority 0.5: Namespace hoisted on parent as default - inherit with no prefix"
                )
              else
                Decision.prefix(
                  prefix: prefix,
                  namespace_class: context.namespace_class,
                  reason: "Priority 0.5: Namespace hoisted on parent as prefix - use parent's prefix"
                )
              end
            end
          end
        end
      end
    end
  end
end
