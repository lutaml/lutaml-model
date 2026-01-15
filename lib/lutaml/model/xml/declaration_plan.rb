# frozen_string_literal: true

require_relative "namespace_declaration"
require_relative "namespace_declaration_data"
require_relative "declaration_plan/element_node"
require_relative "declaration_plan/attribute_node"

module Lutaml
  module Model
    module Xml
      # Represents the complete namespace declaration plan for an XML element
      #
      # DeclarationPlan uses a TREE STRUCTURE that is isomorphic to XmlDataModel,
      # enabling index-based parallel traversal for W3C-compliant attribute prefix handling.
      #
      # The tree consists of ElementNode objects (containing AttributeNode arrays),
      # structured identically to the XmlDataModel tree to enable position-based matching.
      #
      # @example Creating a tree-mode declaration plan
      #   root_node = DeclarationPlan::ElementNode.new(...)
      #   plan = DeclarationPlan.new(root_node: root_node, global_prefix_registry: {...})
      #
      class DeclarationPlan
        # @return [ElementNode] Root of the element tree containing all decisions
        attr_reader :root_node

        # @return [Hash<String, String>] Global prefix registry (URI => prefix)
        attr_reader :global_prefix_registry

        # @return [Hash<String, Symbol>] Input format tracking (URI => :default or :prefix)
        attr_reader :input_formats

        # @return [Hash<String, Class>] Namespace classes by URI (for namespace lookup)
        attr_reader :namespace_classes

        # @return [Hash] Children plans (for collection items)
        attr_reader :children_plans

        # Initialize a declaration plan with tree structure
        #
        # @param root_node [ElementNode] Root element node
        # @param global_prefix_registry [Hash<String, String>] Global prefix registry
        # @param input_formats [Hash<String, Symbol>] Input format tracking (URI => format)
        # @param namespace_classes [Hash<String, Class>] Namespace classes by URI
        # @param children_plans [Hash] Children plans for collections
        def initialize(root_node:, global_prefix_registry: {}, input_formats: {}, namespace_classes: {}, children_plans: {})
          @root_node = root_node
          @global_prefix_registry = global_prefix_registry
          @input_formats = input_formats
          @namespace_classes = namespace_classes
          @children_plans = children_plans
        end

        # Create an empty plan (for compatibility)
        #
        # @return [DeclarationPlan] Empty plan instance
        def self.empty
          empty_node = ElementNode.new(
            qualified_name: "",
            use_prefix: nil,
            hoisted_declarations: {}
          )
          new(root_node: empty_node, global_prefix_registry: {})
        end

        # Create DeclarationPlan from parsed XML input namespaces
        # Used during deserialization to capture input format for round-trip preservation
        #
        # @param input_namespaces [Hash] Namespace declarations from parsed XML
        # @param mapping [Xml::Mapping] XML mapping
        # @return [DeclarationPlan] Plan capturing input format
        def self.from_input(input_namespaces, mapping)
          # Create minimal tree with just root node capturing input xmlns
          hoisted = {}

          # Track input formats
          input_formats = {}

          input_namespaces.each do |key, ns_config|
            prefix = ns_config[:prefix]
            uri = ns_config[:uri]
            format = ns_config[:format] || (prefix ? :prefix : :default)

            # CRITICAL: Hash key based on FORMAT
            # nil = default namespace (xmlns="...")
            # "prefix" = prefixed namespace (xmlns:prefix="...")
            xmlns_key = if format == :default
                          nil
                        else
                          prefix
                        end
            hoisted[xmlns_key] = uri

            # Track format used in input for this URI
            input_formats[uri] = format
          end

          # Build global prefix registry (only for prefixed namespaces)
          registry = {}
          input_namespaces.each_value do |ns_config|
            if ns_config[:format] == :prefix && ns_config[:prefix]
              registry[ns_config[:uri]] = ns_config[:prefix]
            end
          end

          root_node = ElementNode.new(
            qualified_name: mapping.root_element || "",
            use_prefix: nil,  # Will be determined from input_formats
            hoisted_declarations: hoisted
          )

          new(root_node: root_node, global_prefix_registry: registry, input_formats: input_formats)
        end

        # Get namespace declarations as a Hash
        #
        # Converts hoisted_declarations into NamespaceDeclaration objects
        # for querying and inspection.
        #
        # @return [Hash<String, NamespaceDeclaration>] Map of namespace key => declaration
        def namespaces
          return {} unless @namespace_classes

          result = {}
          @namespace_classes.each do |uri, ns_class|
            key = ns_class.to_key

            # Determine format by checking hoisted_declarations
            # Priority: input_formats (for preservation) > hoisted_declarations (actual format) > default
            format = @input_formats[uri]
            prefix_override = nil
            unless format
              # Check hoisted_declarations to see what format is actually being used
              # hoisted_declarations keys: nil = default format, "prefix" = prefix format
              hoisted_key = @root_node.hoisted_declarations.key(uri)

              if @root_node.hoisted_declarations.value?(uri)
                # Namespace IS in hoisted_declarations - check what key it has
                hoisted_key = @root_node.hoisted_declarations.key(uri)
                if hoisted_key.nil?
                  # Namespace found with nil key = default format
                  format = :default
                else
                  # Namespace found with prefix key = prefix format
                  format = :prefix
                  # Set prefix_override to the actual prefix being used
                  prefix_override = hoisted_key
                end
              else
                # Namespace NOT found in hoisted_declarations, use default logic
                # For root elements, prefer default format unless namespace has prefix_default and no hoisted
                format = ns_class.prefix_default ? :prefix : :default
              end
            end

            data = NamespaceDeclarationData.new(
              namespace_class: ns_class,
              format: format,
              declared_at: :here,
              source: nil,
              prefix_override: prefix_override
            )
            result[key] = NamespaceDeclaration.new(data)
          end
          result
        end

        # Get a specific namespace declaration by key
        #
        # @param key [String] Namespace key (e.g., namespace class to_key)
        # @return [NamespaceDeclaration, nil] Namespace declaration or nil if not found
        def namespace(key)
          namespaces[key]
        end

        # Get child element plan by attribute name
        #
        # @param name [Symbol] Child attribute name
        # @return [DeclarationPlan, nil] Child plan or nil if not found
        def child_plan(name)
          @children_plans&.dig(name)
        end
      end
    end
  end
end