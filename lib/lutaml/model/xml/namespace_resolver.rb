# frozen_string_literal: true

require_relative "declaration_plan"

module Lutaml
  module Model
    module Xml
      # Encapsulates all namespace resolution logic for XML serialization
      #
      # Responsibilities:
      # - Extract strategy from DeclarationPlan
      # - Determine prefix usage
      # - Determine xmlns="" requirements
      # - Calculate final namespace URI
      #
      # This module provides a single source of truth for namespace decisions,
      # reducing code duplication across adapters and enabling easier testing.
      class NamespaceResolver
        attr_reader :register

        def initialize(register)
          @register = register
        end

        # Resolve namespace for an element
        #
        # @param rule [MappingRule] the mapping rule
        # @param attribute [Attribute] the attribute definition
        # @param mapping [Mapping] the parent mapping
        # @param plan [DeclarationPlan] the namespace plan
        # @param options [Hash] serialization options
        # @return [Hash] namespace resolution result with keys:
        #   - :blank_xmlns - Whether xmlns="" should be added
        #   - :use_prefix - Whether to use prefix format
        #   - :prefix - The prefix to use (if any)
        #   - :uri - The namespace URI
        #   - :ns_info - Full namespace info from rule.resolve_namespace
        def resolve_for_element(rule, attribute, mapping, plan, options)
          # Get form_default from parent's schema (namespace class)
          form_default = mapping&.namespace_class&.element_form_default || :qualified

          # Resolve element's namespace first to know which namespace we're dealing with
          temp_ns_info = rule.resolve_namespace(
            attr: attribute,
            register: @register,
            parent_ns_uri: mapping&.namespace_uri,
            parent_ns_class: mapping&.namespace_class,
            form_default: form_default,
            use_prefix: false, # Temporary, just to get namespace
            parent_prefix: nil,
          )

          element_ns_uri = temp_ns_info[:uri]

          # Check if strategy exists for this element
          strategy = plan&.element_strategy(rule.to)

          if strategy
            resolve_from_strategy(strategy, rule, attribute, mapping, plan, options, element_ns_uri, form_default)
          else
            resolve_from_legacy_logic(rule, attribute, mapping, plan, options, element_ns_uri, form_default)
          end
        end

        # Check if xmlns="" should be added to attributes
        #
        # @param ns_result [Hash] result from resolve_for_element
        # @param parent_uses_default_ns [Boolean] parent uses default namespace format
        # @return [Boolean] true if xmlns="" should be added
        def xmlns_blank_required?(ns_result, parent_uses_default_ns)
          ns_result[:blank_xmlns] && parent_uses_default_ns
        end

        private

        def resolve_from_strategy(strategy, rule, attribute, mapping, plan, options, element_ns_uri, form_default)
          result = strategy.resolve

          # Use strategy's decisions
          use_prefix = result[:use_prefix]
          parent_prefix = result[:prefix]

          # Resolve with strategy's use_prefix to get final namespace info
          ns_info = rule.resolve_namespace(
            attr: attribute,
            register: @register,
            parent_ns_uri: mapping&.namespace_uri,
            parent_ns_class: mapping&.namespace_class,
            form_default: form_default,
            use_prefix: use_prefix,
            parent_prefix: parent_prefix,
          )

          # Determine resolved prefix based on strategy and rule
          resolved_prefix = if rule.unqualified?
                              nil
                            elsif rule.namespace_param == :inherit
                              parent_prefix
                            elsif use_prefix && parent_prefix
                              parent_prefix
                            else
                              ns_info[:prefix]
                            end

          {
            blank_xmlns: result[:requires_blank_xmlns] || false,
            use_prefix: use_prefix,
            prefix: resolved_prefix,
            uri: ns_info[:uri],
            ns_info: ns_info,
          }
        end

        def resolve_from_legacy_logic(rule, attribute, mapping, plan, options, element_ns_uri, form_default)
          # NAMESPACE RESOLUTION: Determine if element should use prefix
          # Cases:
          # 1. namespace: :inherit → always use parent prefix
          # 2. Type namespace → use Type's namespace from plan
          # 3. Parent uses prefix format AND element has no explicit/type namespace → inherit parent
          # 4. Element has namespace matching parent → check plan[:namespaces][ns_class]
          # 5. Element has explicit namespace: nil → NO prefix ever

          use_prefix = false
          parent_prefix = nil
          qualification_reason = :implicit  # Default: no explicit directive

          # PRIORITY: Check explicit form and prefix options FIRST
          # These override all other considerations
          if rule.qualified?
            # Explicit form: :qualified - element MUST use prefix
            use_prefix = true
            qualification_reason = :explicit_qualified
            # Find appropriate prefix for the element's namespace
            if element_ns_uri && plan
              ns_decl = plan.namespace_for_class(mapping.namespace_class)
              if ns_decl
                parent_prefix = ns_decl.prefix
              end
            end
          elsif rule.unqualified?
            # Explicit form: :unqualified - element MUST NOT use prefix
            use_prefix = false
            qualification_reason = :explicit_unqualified
            parent_prefix = nil
          elsif rule.namespace_param == :inherit
            # Case 1: Explicit :inherit - always use parent format
            use_prefix = true
            qualification_reason = :explicit_inherit
            if plan && mapping&.namespace_class
              ns_decl = plan.namespace_for_class(mapping.namespace_class)
              if ns_decl
                # CRITICAL: Use the ns_object from plan (may be override with custom prefix)
                parent_prefix = ns_decl.prefix
              end
            end
          elsif plan && plan.type_namespace(rule.to)
            # Case 2: Type namespace - this attribute's type defines its own namespace
            # Priority: Type namespace takes precedence over parent inheritance
            # CRITICAL: Only apply if Type has EXPLICIT xml_namespace declaration
            type_ns_class = plan.type_namespace(rule.to)

            # Get the actual type class to check if it has explicit xml_namespace
            type_class = attribute&.type(@register)
            has_explicit_ns = type_class&.respond_to?(:xml_namespace) && type_class.xml_namespace

            if has_explicit_ns
              key = type_ns_class.to_key
              ns_decl = plan.namespace(key)
              qualification_reason = :type_namespace
              if ns_decl&.prefix_format?
                use_prefix = true
                # Use prefix from namespace declaration (includes override if present)
                parent_prefix = ns_decl.prefix
                # Override element_ns_uri to parent's URI for proper resolution
                element_ns_uri = mapping.namespace_uri
              elsif ns_decl
                # CRITICAL FIX: Also set element_ns_uri for default format
                # Native elements inherit parent's namespace regardless of format
                # This prevents xmlns="" from being added incorrectly
                element_ns_uri = mapping.namespace_uri
              end
            else
              # Native type without explicit xml_namespace
              # Check if it should be qualified by schema default
              if !rule.namespace_set? && element_ns_uri == mapping&.namespace_uri && form_default == :qualified
                # Schema default says elements SHOULD be qualified
                use_prefix = true
                qualification_reason = :explicit_qualified
                ns_decl = plan.namespace_for_class(mapping.namespace_class)
                if ns_decl
                  parent_prefix = ns_decl.prefix
                end
              else
                # No qualification from schema default - treat as implicit
                qualification_reason = :implicit
              end
            end
          elsif !rule.namespace_set? && element_ns_uri == mapping&.namespace_uri && mapping&.namespace_class && plan
            # Case 4: Element implicitly inherits parent's namespace (no explicit directive)
            # BUT check if it's qualified by SCHEMA DEFAULT
            if form_default == :qualified
              # Schema default says elements SHOULD be qualified
              # This is an explicit directive from the schema, so inherit prefix
              use_prefix = true
              qualification_reason = :explicit_qualified
              ns_decl = plan.namespace_for_class(mapping.namespace_class)
              if ns_decl
                parent_prefix = ns_decl.prefix
              end
            else
              # Element's namespace URI matches parent's, but no qualification directive
              # This is IMPLICIT qualification - should NOT inherit prefix presentation
              qualification_reason = :implicit  # stays implicit
              # Don't set use_prefix or parent_prefix - let them stay false/nil
            end
          end

          # Now resolve with correct use_prefix to get final namespace info
          ns_info = rule.resolve_namespace(
            attr: attribute,
            register: @register,
            parent_ns_uri: mapping&.namespace_uri,
            parent_ns_class: mapping&.namespace_class,
            form_default: form_default,
            use_prefix: use_prefix,
            parent_prefix: parent_prefix,
          )

          # CRITICAL FIX: resolved_prefix now depends on qualification_reason
          # Only EXPLICIT directives should inherit prefix presentation
          resolved_prefix = if rule.unqualified?
                              # Explicit form: :unqualified - NEVER use prefix
                              nil
                            elsif qualification_reason == :explicit_inherit
                              # Explicit :inherit - always use parent's prefix
                              parent_prefix
                            elsif qualification_reason == :explicit_qualified && use_prefix
                              # Explicit :qualified directive
                              parent_prefix
                            elsif qualification_reason == :explicit_prefix
                              # Explicit prefix directive
                              parent_prefix
                            elsif qualification_reason == :type_namespace && use_prefix
                              # Type has namespace and in prefix format
                              parent_prefix
                            elsif qualification_reason == :implicit
                              # CRITICAL: No prefix for implicit inheritance
                              # Prevents cascading of `prefix: true` to children
                              nil
                            else
                              # CRITICAL FIX: Look up prefix from PLAN using namespace CLASS
                              # When element has explicit namespace, use namespace CLASS to find declaration
                              # Architecture Principle: XmlNamespace CLASS is atomic unit, not URI alone
                              if rule.namespace_class && plan
                                # Element has explicit namespace class - look it up in plan by key
                                key = rule.namespace_class.to_key
                                ns_decl = plan.namespace(key)
                                if ns_decl && ns_decl.prefix_format?
                                  ns_decl.prefix
                                else
                                  ns_info[:prefix]
                                end
                              else
                                ns_info[:prefix]
                              end
                            end

          # Calculate if xmlns="" is needed based on explicit_blank and parent context
          blank_xmlns = false
          parent_uses_default_ns = options[:parent_uses_default_ns]

          # CRITICAL FIX: xmlns="" ONLY for EXPLICIT :blank namespace
          # When element_ns_uri is nil (no namespace specified), element should silently inherit parent's namespace
          # The blank namespace ≠ "no namespace" - it's an intentional choice to be in the blank namespace
          if ns_info[:explicit_blank] && parent_uses_default_ns
            blank_xmlns = true
          elsif !rule.namespace_set? &&
                !element_ns_uri &&
                parent_uses_default_ns &&
                options[:parent_element_form_default] == :qualified
            # W3C: unqualified native types need xmlns="" when parent uses default format
            blank_xmlns = true
          end

          {
            blank_xmlns: blank_xmlns,
            use_prefix: use_prefix,
            prefix: resolved_prefix,
            uri: ns_info[:uri],
            ns_info: ns_info,
          }
        end
      end
    end
  end
end