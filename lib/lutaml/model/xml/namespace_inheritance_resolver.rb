# frozen_string_literal: true

require_relative "declaration_plan_query"

module Lutaml
  module Model
    module Xml
      # Resolves namespace inheritance between parent and child elements
      #
      # CRITICAL ARCHITECTURAL PRINCIPLE:
      # PREFIX INHERITANCE - If parent declared namespace with PREFIX format,
      # child MUST preserve that format to avoid declaring the same namespace twice.
      #
      # @example
      #   resolver = NamespaceInheritanceResolver.new
      #   result = resolver.resolve_inheritance(ns_class, parent_plan, child_mapping, needs, options)
      #
      class NamespaceInheritanceResolver
        # Result of inheritance resolution
        InheritanceResult = Struct.new(
          :should_declare,      # Boolean: should child declare this namespace?
          :format,              # Symbol: :default or :prefix
          :declared_at,         # Symbol: :here or :inherited
          :prefix_override,     # String: custom prefix override
          keyword_init: true,
        )

        # Initialize resolver
        def initialize; end

        # Resolve namespace inheritance for child element
        #
        # Determines if child should declare namespace and what format to use
        # based on parent's declaration.
        #
        # @param ns_class [Class] XmlNamespace class to inherit
        # @param parent_plan [DeclarationPlan] parent's declaration plan
        # @param child_mapping [Xml::Mapping] child element's mapping
        # @param needs [Hash] namespace needs from collector
        # @param options [Hash] serialization options
        # @param format_chooser [FormatChooser] format decision helper
        # @return [InheritanceResult] inheritance decision result
        def resolve_inheritance(ns_class, parent_plan, child_mapping, needs,
options, format_chooser)
          uri = ns_class.uri
          existing = DeclarationPlanQuery.find_namespace_by_uri(parent_plan, uri)

          # No existing declaration in parent - child should declare
          unless existing
            return no_inheritance(ns_class, child_mapping, needs, options,
                                  format_chooser)
          end

          # Skip if marked for local declaration only
          if existing[:declared_at] == :local_on_use
            return no_inheritance(ns_class, child_mapping, needs, options,
                                  format_chooser)
          end

          # PREFIX INHERITANCE RULE:
          # Parent declared with PREFIX → child MUST preserve PREFIX format
          # Architecture Principle (line 102-114 in original):
          # "If a namespace is hoisted as prefix, all elements in that namespace
          # should also utilize the same prefix"
          if existing[:format] == :prefix
            return InheritanceResult.new(
              should_declare: true,
              format: existing[:format],
              declared_at: existing[:declared_at],
              prefix_override: existing[:prefix],
            )
          end

          # Parent used DEFAULT format - check if we need to redeclare
          default_inheritance(ns_class, existing, parent_plan, child_mapping,
                              needs, options, format_chooser)
        end

        private

        # No inheritance - child declares namespace independently
        def no_inheritance(ns_class, child_mapping, needs, options,
format_chooser)
          format = format_chooser.choose_with_override(child_mapping, ns_class,
                                                       needs, options)
          InheritanceResult.new(
            should_declare: true,
            format: format,
            declared_at: :here,
            prefix_override: extract_prefix_override(options),
          )
        end

        # PREFIX inheritance - preserve parent's prefix format
        def prefix_inheritance(existing)
          InheritanceResult.new(
            should_declare: true,
            format: existing.format,
            declared_at: existing.declared_at.to_sym, # Keep as inherited
            prefix_override: existing.prefix_override, # Preserve parent's override
          )
        end

        # DEFAULT inheritance - check if redeclaration needed
        def default_inheritance(ns_class, existing, parent_plan, child_mapping,
needs, options, format_chooser)
          # Check if parent has a different default namespace
          # Since we're using tree structure, we need to check hoisted_declarations
          parent_default_uri = parent_plan.root_node.hoisted_declarations[nil]

          must_redeclare = parent_default_uri && parent_default_uri != ns_class.uri

          format = format_chooser.choose_with_override(child_mapping,
                                                       ns_class, needs, options)
          if must_redeclare
            # Parent changed default namespace - child MUST redeclare
            # Preserve parent's prefix_override when redeclaring
            inherited_prefix_override = existing[:prefix] || extract_prefix_override(options)
            InheritanceResult.new(
              should_declare: true,
              format: format,
              declared_at: :here, # Must declare here, not inherited
              prefix_override: inherited_prefix_override,
            )
          else
            # Parent used default and child can inherit
            InheritanceResult.new(
              should_declare: true,
              format: format,
              declared_at: :inherited, # Keep as inherited
              prefix_override: extract_prefix_override(options),
            )
          end
        end

        # Extract prefix override from options
        def extract_prefix_override(options)
          custom_prefix = nil
          custom_prefix = options[:prefix] if options[:prefix].is_a?(String)
          custom_prefix ||= options[:use_prefix] if options[:use_prefix].is_a?(String)
          custom_prefix
        end
      end
    end
  end
end
