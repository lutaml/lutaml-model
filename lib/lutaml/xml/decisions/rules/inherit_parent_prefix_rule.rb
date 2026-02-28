# frozen_string_literal: true

# lib/lutaml/model/xml/decisions/rules/inherit_parent_prefix_rule.rb
module Lutaml
  module Xml
      module Decisions
      module Rules
      # Array position 2.5: Inherit parent's prefix format
      #
      # When parent uses prefix format and child shares the same namespace,
      # child should use the same prefix to stay in that namespace.
      #
      # This handles the case where:
      # - Grandparent hoisted namespace as prefix
      # - Parent uses prefix format but doesn't re-declare (already hoisted)
      # - Child needs to use prefix to stay in same namespace
      class InheritParentPrefixRule < DecisionRule
        # Applies when:
        # - Element has namespace
        # - Parent uses prefix format
        # - Element shares parent's namespace
        def applies?(context)
          return false unless context.has_namespace?
          return false unless context.parent_uses_prefix_format?
          return true if context.same_namespace_as_parent?

          false
        end

        # Decision: Use parent's prefix (actual or default)
        def decide(context)
          # Try to get the actual prefix being used by parent from parent_hoisted
          # This handles custom prefix case (e.g., prefix: "v" instead of "vcard")
          prefix = find_prefix_for_namespace(context.parent_hoisted,
                                             context.namespace_uri)

          # If not found in parent_hoisted, check for root_prefix
          # When user specifies prefix: "v", root_prefix contains "v"
          if prefix.nil? && context.root_prefix
            prefix = context.root_prefix
          end

          # Fall back to default prefix if still not found
          prefix ||= context.parent_namespace_class.prefix_default

          Decision.prefix(
            prefix: prefix,
            namespace_class: context.namespace_class,
            reason: "Inherit parent's prefix format",
          )
        end

        private

        # Find the prefix for a namespace URI in the hoisted hash
        #
        # @param hoisted [Hash] Hoisted namespaces {prefix => uri}
        # @param namespace_uri [String] The namespace URI to find
        # @return [String, nil] The prefix, or nil if not found
        def find_prefix_for_namespace(hoisted, namespace_uri)
          return nil unless namespace_uri

          hoisted.find { |_prefix, uri| uri == namespace_uri }&.first
        end
      end
      end
      end
  end
end
