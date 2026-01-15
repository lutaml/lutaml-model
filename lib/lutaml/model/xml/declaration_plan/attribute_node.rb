# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      class DeclarationPlan
        # AttributeNode represents the namespace prefix decision for a single XML attribute
        #
        # This is a PURE DATA structure - it stores the W3C-compliant prefix decision
        # made by DeclarationPlanner but contains NO decision-making logic itself.
        #
        # The key field is `use_prefix`:
        # - nil => attribute has NO prefix (W3C :unqualified or blank namespace)
        # - String => attribute uses this specific prefix
        #
        # @example Same namespace, unqualified (NO prefix)
        #   # Element in ParentNs, attribute in ParentNs, attributeFormDefault: :unqualified
        #   attr_node = AttributeNode.new(
        #     local_name: "parent_ns_attr",
        #     use_prefix: nil,  # NO prefix (W3C compliant)
        #     namespace_uri: "http://example.com/parent"
        #   )
        #   attr_node.qualified_name  # => "parent_ns_attr" (no prefix)
        #
        # @example Different namespace (WITH prefix)
        #   # Element in ParentNs, attribute in ChildNs
        #   attr_node = AttributeNode.new(
        #     local_name: "child_attr",
        #     use_prefix: "child",  # YES prefix
        #     namespace_uri: "http://example.com/child"
        #   )
        #   attr_node.qualified_name  # => "child:child_attr"
        #
        class AttributeNode
          # @return [String] Attribute local name (without prefix)
          attr_reader :local_name

          # @return [String, nil] Prefix to use for this attribute
          #   nil = no prefix (W3C :unqualified or blank namespace)
          #   String = use this prefix
          attr_reader :use_prefix

          # @return [String, nil] Namespace URI for this attribute
          attr_reader :namespace_uri

          # Initialize an attribute node
          #
          # @param local_name [String] Attribute name without prefix
          # @param use_prefix [String, nil] Prefix for attribute (nil = no prefix)
          # @param namespace_uri [String, nil] Namespace URI
          def initialize(local_name:, use_prefix:, namespace_uri: nil)
            @local_name = local_name
            @use_prefix = use_prefix
            @namespace_uri = namespace_uri
          end

          # Get the qualified attribute name (with prefix if applicable)
          #
          # This is what adapters should use when creating XML attributes.
          #
          # @return [String] Qualified name: "prefix:name" or "name"
          def qualified_name
            use_prefix ? "#{use_prefix}:#{local_name}" : local_name
          end

          # Check if attribute has a prefix
          #
          # @return [Boolean] true if prefix present
          def prefixed?
            !use_prefix.nil?
          end

          # Check if attribute is unqualified (no prefix)
          #
          # @return [Boolean] true if no prefix
          def unqualified?
            use_prefix.nil?
          end
        end
      end
    end
  end
end