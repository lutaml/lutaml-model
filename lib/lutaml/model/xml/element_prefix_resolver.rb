# frozen_string_literal: true

require_relative "declaration_plan_query"

module Lutaml
  module Model
    module Xml
      # ElementPrefixResolver - Determine element prefix from namespace declaration plan
      #
      # Extracts common logic for resolving element prefixes across all XML adapters.
      # Handles prefix format detection and namespace declaration lookups.
      #
      # @example Usage in adapter
      #   prefix_info = ElementPrefixResolver.resolve(
      #     mapping: xml_mapping,
      #     plan: plan
      #   )
      #   prefix = prefix_info[:prefix]
      #   xml.create_and_add_element(tag_name, prefix: prefix, attributes: attributes)
      module ElementPrefixResolver
        # Resolve element prefix from namespace declaration plan
        #
        # Determines if element should use a prefix based on:
        # - Whether namespace class uses prefix format
        # - The prefix defined in the namespace declaration
        #
        # @param mapping [Mapping] the XML mapping for the element
        # @param plan [DeclarationPlan] the namespace declaration plan
        # @return [Hash] prefix info with keys:
        #   - :prefix [String, nil] - the prefix to use (nil for default namespace)
        #   - :ns_info [Hash, nil] - the namespace info from plan
        def self.resolve(mapping:, plan:)
          prefix = nil
          ns_info = nil

          if mapping.namespace_class
            uri = mapping.namespace_class.uri
            ns_info = DeclarationPlanQuery.find_namespace_by_uri(plan, uri)

            if ns_info && ns_info[:format] == :prefix
              # Use prefix from namespace info
              prefix = ns_info[:prefix]
            end
          end

          {
            prefix: prefix,
            ns_info: ns_info,
          }
        end
      end
    end
  end
end