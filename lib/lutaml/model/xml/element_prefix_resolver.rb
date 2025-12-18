# frozen_string_literal: true

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
        #   - :ns_decl [NamespaceDeclaration, nil] - the namespace declaration
        def self.resolve(mapping:, plan:)
          prefix = nil
          ns_decl = nil

          if mapping.namespace_class
            key = mapping.namespace_class.to_key
            ns_decl = plan.namespace(key)

            if ns_decl&.prefix_format?
              # Use prefix from namespace declaration (includes override if present)
              # The ns_object may have a custom prefix override
              prefix = ns_decl.prefix
            end
          end

          {
            prefix: prefix,
            ns_decl: ns_decl,
          }
        end
      end
    end
  end
end