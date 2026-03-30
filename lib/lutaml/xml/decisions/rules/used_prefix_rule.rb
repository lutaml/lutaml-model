# frozen_string_literal: true

module Lutaml
  module Xml
    module Decisions
      module Rules
        # Priority 0.15: Preserve used prefix from deserialization
        #
        # When an element was deserialized from XML with a specific prefix, preserve
        # that prefix during serialization for round-trip fidelity.
        #
        # This handles the dual-namespace case where multiple elements with the same
        # local name but different namespaces (e.g., m:rPr and w:rPr) need to preserve
        # their respective prefixes during round-trip.
        #
        # CRITICAL: Only applies when parent has a namespace. This prevents the rule
        # from incorrectly applying when the parent has no namespace (where elements
        # should use default format).
        class UsedPrefixRule < DecisionRule
          # Priority 0.15 - Between InheritFromParentRule (0) and ElementFormDefaultUnqualifiedRule (0.5)
          def priority
            0.15
          end

          # Applies when:
          # - Element has a used_prefix from deserialization
          # - Element is not the root (root uses model's prefix_default)
          # - The used_prefix matches the namespace's prefix_default
          # - Parent's XmlElement has a non-nil namespace_prefix
          #   (i.e., parent used prefix format, not default namespace format)
          # - Namespace has element_form_default :qualified set
          #   (namespaces without explicit :qualified should use default format)
          #
          # This handles the dual-namespace case where multiple elements with the same
          # local name but different namespaces (e.g., m:rPr and w:rPr) need to preserve
          # their respective prefixes during round-trip.
          def applies?(context)
            return false if context.root?
            return false unless context.has_namespace?
            return false if context.element_used_prefix.nil? || context.element_used_prefix.empty?

            ns_class = context.namespace_class

            # Skip if namespace does NOT have element_form_default :qualified
            # Namespaces without explicit :qualified should use default format
            # (e.g., dcterms namespace uses default format, not prefix)
            return false unless ns_class.respond_to?(:element_form_default_set?) &&
                                ns_class.element_form_default_set? &&
                                ns_class.element_form_default == :qualified

            # The used_prefix should match the namespace's prefix_default
            # AND parent must have actually used prefix format (not default namespace)
            context.namespace_class.prefix_default == context.element_used_prefix &&
              !context.parent_namespace_prefix.nil? &&
              !context.parent_namespace_prefix.empty?
          end

          # Decision: Use the used prefix from deserialization
          def decide(context)
            Decision.prefix(
              prefix: context.element_used_prefix,
              namespace_class: context.namespace_class,
              reason: "Priority 0.15: Preserve used prefix from deserialization for round-trip",
            )
          end
        end
      end
    end
  end
end
