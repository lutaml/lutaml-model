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

            # When a child element has its own namespace that differs from the
            # parent's, preserving the input format is critical for round-trip
            # fidelity. Using prefix format (xmlns:prefix="uri") preserves the
            # parent's default namespace scope, while switching to default format
            # (xmlns="uri") would override it, changing the namespace context for
            # the element and its descendants.
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
              # For nested elements, use element_used_prefix which is correctly set
              # during deserialization. For root elements, use element_namespace_prefix
              # which reads from the original XmlElement.
              prefix = if context.root?
                         context.element_namespace_prefix
                       else
                         context.element_used_prefix
                       end
              Decision.prefix(
                prefix: prefix,
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
