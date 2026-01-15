# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # Strategy for resolving namespace for an XML element
      #
      # Encapsulates the logic for determining:
      # - Whether element should use prefix
      # - Which prefix to use
      # - Which namespace URI applies
      # - Whether xmlns="" should be explicitly added
      #
      # This is created by DeclarationPlanner and stored in DeclarationPlan
      # for execution by adapters.
      #
      # @example Using a strategy
      #   strategy = BlankNamespaceStrategy.new
      #   ns_info = strategy.resolve
      #   # => { use_prefix: false, prefix: nil, uri: nil, requires_blank_xmlns: false }
      #
      class NamespaceResolutionStrategy
        attr_reader :use_prefix, :prefix, :namespace_uri, :requires_blank_xmlns

        # Initialize the strategy with namespace resolution info
        #
        # @param use_prefix [Boolean] Whether to use prefix format
        # @param prefix [String, nil] The prefix to use (if any)
        # @param namespace_uri [String, nil] The namespace URI (if any)
        # @param requires_blank_xmlns [Boolean] Whether to explicitly add xmlns=""
        def initialize(use_prefix:, prefix: nil, namespace_uri: nil, requires_blank_xmlns: false)
          @use_prefix = use_prefix
          @prefix = prefix
          @namespace_uri = namespace_uri
          @requires_blank_xmlns = requires_blank_xmlns
        end

        # Returns namespace info ready for adapter use
        #
        # @return [Hash] Hash with :use_prefix, :prefix, :uri, :requires_blank_xmlns keys
        def resolve
          {
            use_prefix: @use_prefix,
            prefix: @prefix,
            uri: @namespace_uri,
            requires_blank_xmlns: @requires_blank_xmlns
          }
        end
      end

      # Strategy for elements that should be in blank namespace
      #
      # Used for native types (`:string`, `:integer`, etc.) WITHOUT explicit
      # `xml_namespace` declaration. These elements should serialize in the
      # blank namespace even when their parent uses a namespace.
      #
      # W3C Compliance:
      # - If parent uses PREFIX format: no xmlns needed
      # - If parent uses DEFAULT format: xmlns="" must be added to prevent inheritance
      #
      # @example XML output with parent using prefix format
      #   <first:parent xmlns:first="http://example.com">
      #     <child>value</child>  <!-- blank namespace, no xmlns needed -->
      #   </first:parent>
      #
      # @example XML output with parent using default format
      #   <parent xmlns="http://example.com">
      #     <child xmlns="">value</child>  <!-- xmlns="" prevents inheritance -->
      #   </parent>
      #
      class BlankNamespaceStrategy < NamespaceResolutionStrategy
        # Initialize with blank namespace settings
        #
        # @param parent_uses_default [Boolean] Whether parent uses default namespace format
        def initialize(parent_uses_default: false)
          super(
            use_prefix: false,
            prefix: nil,
            namespace_uri: nil,
            requires_blank_xmlns: parent_uses_default
          )
        end
      end

      # Strategy for elements inheriting parent namespace
      #
      # Used when element should inherit the namespace from its parent element,
      # such as when `element_form_default: :qualified` is set and no explicit
      # namespace directive is given.
      #
      # @example Inheriting default namespace
      #   <parent xmlns="http://example.com">
      #     <child>value</child>  <!-- inherits default namespace -->
      #   </parent>
      #
      # @example Inheriting prefixed namespace
      #   <test:parent xmlns:test="http://example.com">
      #     <test:child>value</test:child>  <!-- inherits prefix -->
      #   </test:parent>
      #
      class InheritedNamespaceStrategy < NamespaceResolutionStrategy
        # Initialize from parent namespace declaration
        #
        # @param parent_ns_decl [NamespaceDeclaration] Parent's namespace declaration
        def initialize(parent_ns_decl)
          super(
            use_prefix: parent_ns_decl.prefix_format?,
            prefix: parent_ns_decl.prefix,
            namespace_uri: parent_ns_decl.uri
          )
        end
      end

      # Strategy for Type::Value with explicit xml_namespace
      #
      # Used when a custom Type::Value class declares its own namespace via
      # `xml_namespace MyNamespace`. The type's namespace takes precedence
      # over parent namespace.
      #
      # @example Custom Type with namespace
      #   class CustomName < Lutaml::Model::Type::String
      #     xml_namespace MyNamespace
      #   end
      #
      #   <parent xmlns="http://example.com/parent">
      #     <custom:name xmlns:custom="http://example.com/custom">value</custom:name>
      #   </parent>
      #
      class TypeNamespaceStrategy < NamespaceResolutionStrategy
        # Initialize from type namespace declaration
        #
        # @param type_ns_decl [NamespaceDeclaration] Type's namespace declaration
        # @param type_class [Class] The Type::Value class (for reference)
        def initialize(type_ns_decl, type_class)
          super(
            use_prefix: type_ns_decl.prefix_format?,
            prefix: type_ns_decl.prefix,
            namespace_uri: type_class.xml_namespace.uri
          )
        end
      end

      # Strategy for elements qualified by schema's element_form_default
      #
      # Used when element inherits parent namespace due to schema's
      # `element_form_default: :qualified` setting (not explicit directive).
      #
      # CRITICAL DIFFERENCE from InheritedNamespaceStrategy:
      # - InheritedNamespaceStrategy: explicit `namespace: :inherit` directive
      # - SchemaQualifiedStrategy: implicit qualification from schema default
      #
      # Both inherit parent's namespace AND prefix format (presentation).
      #
      # @example Schema-qualified element with parent using prefix
      #   class ParentNamespace < Lutaml::Model::Xml::W3c::XmlNamespace
      #     uri "http://example.com"
      #     prefix_default "ex"
      #     element_form_default :qualified
      #   end
      #
      #   <ex:parent xmlns:ex="http://example.com">
      #     <ex:child>value</ex:child>  <!-- inherits prefix from schema default -->
      #   </ex:parent>
      #
      # @example Schema-qualified element with parent using default
      #   <parent xmlns="http://example.com">
      #     <child>value</child>  <!-- inherits default namespace from schema -->
      #   </parent>
      #
      class SchemaQualifiedStrategy < NamespaceResolutionStrategy
        # Initialize from parent namespace declaration
        #
        # @param parent_ns_decl [NamespaceDeclaration] Parent's namespace declaration
        def initialize(parent_ns_decl)
          super(
            use_prefix: parent_ns_decl.prefix_format?,
            prefix: parent_ns_decl.prefix,
            namespace_uri: parent_ns_decl.uri
          )
        end
      end

      # Strategy for elements with explicit namespace directive
      #
      # Used when element has explicit namespace configuration via:
      # - `namespace: :inherit`
      # - `namespace: "http://...", prefix: "pfx"`
      # - Element is `qualified?` or `unqualified?`
      #
      # @example Explicit qualification
      #   xml do
      #     map_element "name", to: :name, namespace: :inherit
      #   end
      #
      class ExplicitNamespaceStrategy < NamespaceResolutionStrategy
        # Initialize from namespace declaration and mapping rule
        #
        # @param ns_decl [NamespaceDeclaration] The namespace declaration
        # @param mapping_rule [Xml::MappingRule] The element's mapping rule
        def initialize(ns_decl, mapping_rule)
          use_prefix = determine_use_prefix(ns_decl, mapping_rule)
          super(
            use_prefix: use_prefix,
            prefix: use_prefix ? ns_decl.prefix : nil,
            namespace_uri: ns_decl.uri
          )
        end

        private

        # Determine if prefix format should be used
        #
        # @param ns_decl [NamespaceDeclaration] The namespace declaration
        # @param rule [Xml::MappingRule] The mapping rule
        # @return [Boolean] true if prefix format should be used
        def determine_use_prefix(ns_decl, rule)
          # Explicit unqualified always means no prefix
          return false if rule.unqualified?

          # Explicit qualified or prefix_set always means use prefix
          return true if rule.qualified? || rule.prefix_set?

          # Otherwise, follow namespace's format preference
          ns_decl.prefix_format?
        end
      end
    end
  end
end