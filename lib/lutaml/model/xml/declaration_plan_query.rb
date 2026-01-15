# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # Query helper for DeclarationPlan tree structure
      #
      # Provides OOP interface for extracting namespace information
      # from DeclarationPlan without adding query methods to plan itself.
      #
      # ARCHITECTURE: Separate query logic from data structure (MECE)
      #
      # DeclarationPlan is a pure data structure (tree of ElementNode objects).
      # This module contains all query/search logic for that structure.
      module DeclarationPlanQuery
        # Find namespace declaration in plan by URI
        #
        # Searches the root node's hoisted declarations for a namespace
        # with the given URI and returns information about it.
        #
        # @param plan [DeclarationPlan] The declaration plan
        # @param uri [String] Namespace URI to search for
        # @return [Hash, nil] { prefix: String|nil, format: Symbol, declared_at: Symbol, uri: String }
        #   - prefix: nil for default format, "prefix" for prefix format
        #   - format: :default or :prefix
        #   - declared_at: :here (root hoisted) or :local_on_use
        #   - uri: the namespace URI
        def self.find_namespace_by_uri(plan, uri)
          # Search root_node.hoisted_declarations
          plan.root_node.hoisted_declarations.each do |xmlns_key, xmlns_uri|
            next unless xmlns_uri == uri

            return {
              prefix: xmlns_key,              # nil or "prefix"
              format: xmlns_key ? :prefix : :default,
              declared_at: :here,
              uri: uri
            }
          end

          nil
        end

        # Check if element needs xmlns="" based on plan
        #
        # An element needs xmlns="" if:
        # 1. It has no namespace (blank namespace)
        # 2. Its parent uses default namespace format (xmlns="...")
        #
        # This is W3C compliant - blank namespace children must explicitly
        # opt out of parent's default namespace.
        #
        # @param plan [DeclarationPlan] The declaration plan
        # @param element [XmlDataModel::XmlElement] Element to check
        # @return [Boolean] true if element needs xmlns=""
        def self.element_needs_xmlns_blank?(plan, element)
          # Element with namespace doesn't need xmlns=""
          return false if element.namespace_class

          # Check if root declares default namespace (xmlns="...")
          # If root has default namespace (key nil), blank children need xmlns=""
          plan.root_node.hoisted_declarations.key?(nil)
        end

        # Check if namespace is declared at root with default format
        #
        # This is useful for determining if child elements can inherit
        # via the default namespace without needing prefixes.
        #
        # @param plan [DeclarationPlan] The declaration plan
        # @param namespace_class [Class] XmlNamespace class
        # @return [Boolean] true if declared at root with default format
        def self.declared_at_root_default_format?(plan, namespace_class)
          return false unless namespace_class
          return false if namespace_class == :blank  # :blank has no URI

          uri = namespace_class.uri
          ns_info = find_namespace_by_uri(plan, uri)

          ns_info && ns_info[:declared_at] == :here && ns_info[:format] == :default
        end

        # Check if namespace uses prefix format in plan
        #
        # @param plan [DeclarationPlan] The declaration plan
        # @param namespace_class [Class] XmlNamespace class
        # @return [Boolean] true if namespace uses prefix format
        def self.prefix_format?(plan, namespace_class)
          return false unless namespace_class
          return false if namespace_class == :blank  # :blank has no URI

          uri = namespace_class.uri
          ns_info = find_namespace_by_uri(plan, uri)

          ns_info && ns_info[:format] == :prefix
        end

        # Get prefix for namespace from plan
        #
        # Returns the prefix string if namespace uses prefix format,
        # or nil if it uses default format or is not found.
        #
        # @param plan [DeclarationPlan] The declaration plan
        # @param namespace_class [Class] XmlNamespace class
        # @return [String, nil] Prefix string or nil
        def self.prefix_for(plan, namespace_class)
          return nil unless namespace_class
          return nil if namespace_class == :blank  # :blank has no URI

          uri = namespace_class.uri
          ns_info = find_namespace_by_uri(plan, uri)

          ns_info&.dig(:prefix)
        end
      end
    end
  end
end