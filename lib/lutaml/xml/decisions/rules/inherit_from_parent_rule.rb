# frozen_string_literal: true

module Lutaml
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
          # - Child does NOT have its own prefix from deserialization
          #   (if child has its own prefix, FormatPreservationRule should handle it)
          def applies?(context)
            return false unless context.has_namespace?
            return false unless context.parent_uses_default_format?

            # If child has its own used prefix from deserialization, don't inherit.
            # Let FormatPreservationRule handle it to preserve the child's prefix.
            return false if context.element_used_prefix

            # Case 1: Both parent and child have explicit namespace_class in same namespace
            return true if context.same_namespace_as_parent?

            # Case 2: Parent has default namespace declared and child's namespace matches it
            context.namespace_matches_parent_default?
          end

          # Decision: Use default format to inherit
          def decide(context)
            Decision.default(
              namespace_class: context.namespace_class,
              reason: "Priority 0: Inherit parent's default namespace",
            )
          end
        end
      end
    end
  end
end
