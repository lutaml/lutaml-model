# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # AttributeNamespaceResolver - Handle attribute namespace resolution
      #
      # Extracts common logic for resolving attribute namespaces across all XML adapters.
      # Handles W3C attributeFormDefault semantics and local namespace declarations.
      #
      # @example Usage in adapter
      #   ns_info = AttributeNamespaceResolver.resolve(
      #     rule: attribute_rule,
      #     attribute: attr,
      #     plan: plan,
      #     mapper_class: mapper_class,
      #     register: @register
      #   )
      #   attr_name = ns_info[:qualified_name]
      #   attributes[attr_name] = value
      module AttributeNamespaceResolver
        # Resolve attribute namespace from mapping rule and attribute definition
        #
        # Handles W3C attributeFormDefault semantics:
        # - Unqualified attributes in same namespace as element → NO prefix
        # - Qualified attributes → use prefix
        #
        # @param rule [MappingRule] the attribute mapping rule
        # @param attribute [Attribute] the attribute definition
        # @param plan [DeclarationPlan] the namespace declaration plan
        # @param mapper_class [Class] the model class being serialized
        # @param register [Symbol] the model register
        # @return [Hash] namespace info with keys:
        #   - :prefix [String, nil] - namespace prefix to use (nil for no prefix)
        #   - :uri [String, nil] - namespace URI
        #   - :unqualified_same_ns [Boolean] - true if unqualified in same namespace as element
        #   - :needs_local_declaration [Boolean] - true if xmlns declaration needed
        #   - :local_xmlns_attr [String, nil] - the xmlns attribute name if declaration needed
        #   - :local_xmlns_uri [String, nil] - the xmlns URI value if declaration needed
        def self.resolve(rule:, attribute:, plan:, mapper_class:, register:)
          # Get parent namespace class if available
          parent_ns_class = if mapper_class.respond_to?(:mappings_for)
                              mapper_class.mappings_for(:xml)&.namespace_class
                            end

          # Get attribute form default from parent's schema (namespace class)
          form_default = parent_ns_class&.attribute_form_default || :unqualified

          # Resolve base namespace using MappingRule
          ns_info = rule.resolve_namespace(
            attr: attribute,
            register: register,
            parent_ns_uri: parent_ns_class&.uri,
            parent_ns_class: parent_ns_class,
            form_default: form_default,
          )

          # Determine if attribute's namespace needs local  declaration
          needs_local = false
          local_xmlns_attr = nil
          local_xmlns_uri = nil

          if ns_info[:prefix] && plan && plan.namespaces
            # Find namespace declaration by URI or prefix
            ns_decl = if ns_info[:uri]
                        plan.namespaces.values.find { |decl| decl.uri == ns_info[:uri] }
                      else
                        plan.namespaces.values.find do |decl|
                          decl.ns_object.prefix_default == ns_info[:prefix] ||
                            decl.prefix == ns_info[:prefix]
                        end
                      end

            # Check if namespace is marked for local declaration
            if ns_decl&.local_on_use?
              needs_local = true
              # Handle both default (nil prefix) and prefixed namespaces
              local_xmlns_attr = if ns_info[:prefix]
                                   "xmlns:#{ns_info[:prefix]}"
                                 else
                                   "xmlns"
                                 end
              local_xmlns_uri = ns_decl.uri || ns_decl.ns_object.uri
            end
          end

          # Return complete namespace information
          {
            prefix: ns_info[:prefix],
            uri: ns_info[:uri],
            unqualified_same_ns: ns_info[:unqualified_same_ns],
            needs_local_declaration: needs_local,
            local_xmlns_attr: local_xmlns_attr,
            local_xmlns_uri: local_xmlns_uri,
          }
        end

        # Build qualified attribute name based on namespace resolution
        #
        # Handles W3C attributeFormDefault semantics:
        # - Same namespace, unqualified form → NO prefix (inherits from element)
        # - Different namespace or qualified → use prefix
        #
        # @param ns_info [Hash] namespace info from resolve method
        # @param mapping_rule_name [String] the base attribute name
        # @param attribute_rule [MappingRule] the attribute mapping rule
        # @return [String] the qualified attribute name
        def self.build_qualified_name(ns_info, mapping_rule_name, attribute_rule)
          if ns_info[:unqualified_same_ns]
            # Same namespace, unqualified form → NO prefix
            # Attribute inherits namespace from element's context
            mapping_rule_name
          elsif ns_info[:prefix]
            "#{ns_info[:prefix]}:#{mapping_rule_name}"
          else
            attribute_rule.prefixed_name
          end
        end
      end
    end
  end
end