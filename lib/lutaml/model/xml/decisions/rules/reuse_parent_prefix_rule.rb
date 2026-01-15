# frozen_string_literal: true

require_relative "../decision_rule"

module Lutaml
  module Model
    module Xml
          module Decisions
            module Rules
              # Priority 0.25: Reuse parent's prefix for namespace rebinding
              #
              # When parent uses prefix format and has a different namespace URI than child,
              # child should reuse parent's prefix but declare its own namespace URI locally.
              # This is called "namespace rebinding" in XML.
              #
              # Only applies when use_prefix: true is set (not custom string prefixes).
              class ReuseParentPrefixRule < DecisionRule
                # Priority 0.6 - Between HoistedOnParentRule (0.5) and ExplicitOptionRule (0.75)
                def priority
                  0.6
                end

                # Applies when:
                # 1. Element has a namespace
                # 2. Parent uses prefix format (indicating root has use_prefix: true)
                # 3. Parent has a prefix hoisted
                # 4. Element's namespace URI is NOT already hoisted by parent
                # 5. Element's namespace's prefix_default does NOT match parent's prefix
                #    (if they match, child should use default format instead of reusing)
                # 6. There are Type namespaces that need prefix format
                #    (only reuse prefix when Type namespaces require prefixed declarations)
                def applies?(context)
                  return false unless context.has_namespace?
                  # Check if parent uses prefix format (indicating root has use_prefix: true)
                  # We can't use explicit_prefix_option since we don't propagate use_prefix to children
                  return false unless context.parent_format == :prefix
                  return false unless context.parent_hoisted.any?

                  # Check if element's namespace URI is NOT in parent's hoisted namespaces
                  # If parent already hoisted this namespace, let HoistedOnParentRule handle it
                  return false if context.hoisted_on_parent?

                  # Get parent's first prefix
                  parent_prefix = context.parent_hoisted.first&.first

                  # CRITICAL: If child's namespace has same prefix_default as parent's prefix,
                  # child should use DEFAULT format instead of reusing parent's prefix.
                  # This prevents conflicting namespace declarations.
                  child_default_prefix = context.namespace_class.prefix_default
                  return false if child_default_prefix == parent_prefix

                  # CRITICAL: Only reuse parent's prefix when there are Type namespaces
                  # that need prefix format. Without Type namespaces, child should use
                  # default format for its own namespace.
                  # Type namespaces always use prefix format (W3C constraint: only one
                  # default namespace per element, so Type namespaces MUST use prefixes).
                  return false unless context.has_type_namespaces?

                  true
                end

                # Decision: Reuse parent's prefix but will declare namespace locally
                def decide(context)
                  # Get parent's first prefix
                  parent_prefix = context.parent_hoisted.first&.first

                  if parent_prefix
                    Decision.prefix(
                      prefix: parent_prefix,
                      namespace_class: context.namespace_class,
                      reason: "Priority 0.6: Reuse parent's prefix for namespace rebinding (use_prefix: true)"
                    )
                  else
                    Decision::NEUTRAL
                  end
                end
              end
            end
        end
    end
  end
end
