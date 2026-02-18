# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # Handles namespace format decision logic (default vs prefix)
      #
      # Implements multi-tier priority system:
      # Tier 1: Stored plan from parsed XML (format preservation)
      # Tier 2: Explicit user preference (options[:prefix])
      # Tier 3: W3C rules (attributes require prefix)
      # Tier 4: Default preference (cleaner)
      #
      # @example
      #   chooser = FormatChooser.new
      #   format = chooser.choose(mapping, ns_class, needs, options)
      #
      class FormatChooser
        # Initialize format chooser with register for type resolution
        #
        # @param register [Symbol] the register ID for type resolution
        def initialize(register = nil)
          @register = register || Lutaml::Model::Config.default_register
        end

        # Choose format for namespace declaration
        #
        # Implements the decision logic:
        # 1. Explicit user preference (options[:prefix] or options[:use_prefix])
        # 2. W3C rule: prefix required if attributes in same namespace
        # 3. Check if we're declaring in child context with qualified elements
        # 4. Default: prefer default namespace (cleaner)
        #
        # @param mapping [Xml::Mapping] the element mapping
        # @param needs [Hash] namespace needs (with string keys)
        # @param options [Hash] serialization options
        # @return [Symbol] :default or :prefix
        def choose(mapping, needs, options)
          return :default unless mapping.namespace_class

          # 1. Explicit user preference via prefix or use_prefix option
          # Check options[:prefix] first for backward compatibility
          if options[:prefix].is_a?(String)
            return :prefix
          elsif options[:use_prefix].is_a?(String)
            return :prefix
          end

          # 2. W3C rule: attributes in own namespace REQUIRE prefix
          # Check if this namespace is used for attributes (by key lookup)
          key = mapping.namespace_class.to_key
          if needs[:namespaces][key]
            ns_entry = needs[:namespaces][key]
            # Own namespace used in attributes → MUST use prefix
            return :prefix if ns_entry[:used_in].include?(:attributes)

            # Cascading prefix: If children need this namespace with prefix, provide it
            return :prefix if ns_entry[:children_need_prefix]
          end

          # 3. Check if any child elements use :inherit
          # If they do and we have a prefix, use prefixed format
          # so children can properly reference the namespace
          if mapping.namespace_class.prefix_default && mapping.respond_to?(:elements)
            has_inherit_children = mapping.elements.any? do |elem_rule|
              elem_rule.namespace_param == :inherit
            end
            return :prefix if has_inherit_children

            # Also check if any children have form: :qualified
            # They need prefixed format to reference parent namespace
            has_qualified_children = mapping.elements.any?(&:qualified?)
            return :prefix if has_qualified_children
          end

          # 4. Default: prefer default namespace (cleaner, no prefix needed)
          :default
        end

        # Choose format for namespace declaration with override support
        #
        # Supports custom prefix overrides and stored plan format preservation.
        # This is the main entry point that includes Tier 1 priority check.
        #
        # @param mapping [Xml::Mapping] the element mapping
        # @param effective_ns_class [Class] the effective namespace class (may be override)
        # @param needs [Hash] namespace needs (with string keys)
        # @param options [Hash] serialization options
        # @param plan [DeclarationPlan, nil] current plan for tier 1 check
        # @return [Symbol] :default or :prefix
        def choose_with_override(mapping, effective_ns_class, needs, options,
plan: nil)
          return :default unless effective_ns_class

          # Tier 1: Check for stored plan format (preserve from parsed XML)
          # CRITICAL: This is the format preservation fix from Session 167
          if plan && options[:__stored_plan]
            stored_plan = options[:__stored_plan]
            input_ns_decl = stored_plan.namespaces.values.find do |decl|
              decl.from_input? && decl.uri == effective_ns_class.uri
            end
            return input_ns_decl.format if input_ns_decl
          elsif plan
            # Fallback: check current plan for input namespaces
            input_ns_decl = plan.namespaces.values.find do |decl|
              decl.from_input? && decl.uri == effective_ns_class.uri
            end
            return input_ns_decl.format if input_ns_decl
          end

          # Tier 2: Explicit user preference via prefix or use_prefix option
          # Check both options[:prefix] (direct call) and options[:use_prefix] (from serialize.rb)
          if options.key?(:prefix)
            case options[:prefix]
            when true, String
              return :prefix
            when false, nil
              return :default
            end
          elsif options.key?(:use_prefix)
            # options[:use_prefix] can be a string (custom prefix) or boolean
            case options[:use_prefix]
            when true, String
              return :prefix
            when false, nil
              return :default
            end
          end

          # Tier 3: W3C rule: attributes in same namespace require prefix
          # Cascading prefix requirement from children
          key = effective_ns_class.to_key
          if needs[:namespaces][key]
            ns_entry = needs[:namespaces][key]
            # Own namespace used in attributes → MUST use prefix
            return :prefix if ns_entry[:used_in].include?(:attributes)

            # Cascading prefix: If children need this namespace with prefix, provide it
            return :prefix if ns_entry[:children_need_prefix]
          end

          # 3. Check if any child elements use :inherit or form: :qualified
          if effective_ns_class.prefix_default && mapping.respond_to?(:elements)
            has_inherit_children = mapping.elements.any? do |elem_rule|
              elem_rule.namespace_param == :inherit
            end
            return :prefix if has_inherit_children

            has_qualified_children = mapping.elements.any?(&:qualified?)
            return :prefix if has_qualified_children
          end

          # Tier 4: Default: prefer default namespace (cleaner, no prefix needed)
          :default
        end

        # Build xmlns declaration string from XmlNamespace class
        #
        # @param ns_class [Class] the XmlNamespace class
        # @param format [Symbol] :default or :prefix
        # @param options [Hash] serialization options (may contain custom prefix)
        # @param prefix_override [String, nil] explicit custom prefix override
        # @return [String] the xmlns declaration attribute
        def build_declaration(ns_class, format, options = {},
prefix_override: nil)
          # CRITICAL: If namespace has no prefix, MUST use default format
          # Using prefix format without a prefix creates invalid xmlns:=""
          if format == :prefix && !ns_class.prefix_default && !prefix_override
            format = :default
          end

          if format == :default
            "xmlns=\"#{ns_class.uri}\""
          else
            # PRIORITY ORDER: explicit override > options > class default
            prefix = prefix_override ||
              (options[:prefix].is_a?(String) ? options[:prefix] : nil) ||
              (options[:use_prefix].is_a?(String) ? options[:use_prefix] : nil) ||
              ns_class.prefix_default
            "xmlns:#{prefix}=\"#{ns_class.uri}\""
          end
        end

        private

        attr_reader :register
      end
    end
  end
end
