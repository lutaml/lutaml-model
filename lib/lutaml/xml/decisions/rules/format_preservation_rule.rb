# frozen_string_literal: true

# lib/lutaml/model/xml/decisions/rules/format_preservation_rule.rb
module Lutaml
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
            return false if context.preserved_input_format.nil?

            # CRITICAL: Don't preserve input format when element has its OWN
            # namespace that differs from parent's namespace.
            # When a child element declares its own namespace (not inherited),
            # it should use default format (W3C minimal-subtree principle).
            # Format preservation is mainly for root elements or elements that
            # share namespace with parent.
            #
            # Skip this check for root elements - they should always preserve format
            if !context.root? && context.namespace_class
              parent_ns = context.parent_namespace_class
              # If parent has no namespace but child has a namespace,
              # don't preserve format - use default format
              # Check both nil and empty URI
              parent_ns_uri = parent_ns&.uri
              if parent_ns.nil? || parent_ns_uri.nil? || parent_ns_uri.empty?
                return false
              end
              # If child's namespace differs from parent's namespace,
              # don't preserve format - use default format
              if context.namespace_class.uri != parent_ns_uri
                return false
              end
            end

            true
          end

          # Decision: Use the format from input
          def decide(context)
            input_format = context.preserved_input_format

            if input_format == :default
              Decision.default(
                namespace_class: context.namespace_class,
                reason: "Priority 1: Input used default format - preserve it",
              )
            else
              Decision.prefix(
                prefix: context.namespace_class.prefix_default,
                namespace_class: context.namespace_class,
                reason: "Priority 1: Input used prefix format - preserve it",
              )
            end
          end
        end
      end
    end
  end
end
