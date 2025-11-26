# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # Phase 2: Declaration Planning
      #
      # Makes top-down declaration decisions using bottom-up knowledge.
      # This ensures "never declare twice" and optimal namespace format selection.
      #
      # CRITICAL ARCHITECTURAL PRINCIPLE:
      # XmlNamespace CLASS is the atomic unit of namespace configuration.
      # Never track URI and prefix separately - they are inseparable.
      #
      # @example
      #   planner = DeclarationPlanner.new(register)
      #   plan = planner.plan(model_instance, mapping, needs)
      #
      class DeclarationPlanner
        # Initialize planner with register for type resolution
        #
        # @param register [Symbol] the register ID for type resolution
        def initialize(register = nil)
          @register = register || Lutaml::Model::Config.default_register

          # Visited type tracking prevents infinite recursion during type analysis
          # When element is nil (type analysis mode), we track which types we've seen
          @visited_types = Set.new
        end

        # Create declaration plan for an element and its descendants
        #
        # @param element [Object] the model instance (can be nil for type analysis)
        # @param mapping [Xml::Mapping] the XML mapping for this element
        # @param needs [Hash] namespace needs from collector (with string keys)
        # @param parent_plan [Hash, nil] parent element's plan
        # @param options [Hash] serialization options
        # @return [Hash] declaration plan structure
        def plan(element, mapping, needs, parent_plan: nil, options: {})
          plan = {
            namespaces: {},        # String key (from to_key) => { ns_object: XmlNamespace CLASS, format:, xmlns_declaration:, declared_at: }
            children_plans: {},    # Child element => child plans
            type_namespaces: {},   # Attribute name => XmlNamespace CLASS
          }

          # Get mapper_class and attributes early for Type namespace lookups
          mapper_class = element&.class || options[:mapper_class]

          # Handle custom prefix override by creating anonymous XmlNamespace class
          # ARCHITECTURAL PRINCIPLE: XmlNamespace CLASS is atomic - same URI + different prefix = different class
          # Check both options[:prefix] (direct call) and options[:use_prefix] (from serialize.rb transformation)
          namespace_class_override = nil
          custom_prefix = options[:prefix] if options[:prefix].is_a?(String)
          custom_prefix ||= options[:use_prefix] if options[:use_prefix].is_a?(String)

          if custom_prefix && mapping.namespace_class
            original_ns = mapping.namespace_class
            namespace_class_override = Class.new(Lutaml::Model::XmlNamespace) do
              uri original_ns.uri
              prefix_default custom_prefix
              # Copy other settings if needed
              element_form_default original_ns.element_form_default if original_ns.respond_to?(:element_form_default)
              attribute_form_default original_ns.attribute_form_default if original_ns.respond_to?(:attribute_form_default)
            end
          end

          # Use override if present, otherwise use mapping's namespace_class
          effective_ns_class = namespace_class_override || mapping.namespace_class

          # Prevent infinite recursion for type analysis (when element is nil)
          if element.nil? && mapper_class
            return empty_plan if @visited_types.include?(mapper_class)

            @visited_types << mapper_class
          end

          attributes = if mapper_class.respond_to?(:attributes)
                         mapper_class.attributes
                       else
                         {}
                       end

          # ==================================================================
          # PHASE 1: INHERIT PARENT NAMESPACE DECLARATIONS
          # ==================================================================
          # Inherit parent's namespace declarations
          if parent_plan
            # CRITICAL: Preserve :local_on_use marker through inheritance
            # Children inherit ALL parent namespaces (:here and :inherited)
            # Only :here becomes :inherited, :inherited stays :inherited
            # :local_on_use stays as :local_on_use so children know to declare locally
            plan[:namespaces] = parent_plan[:namespaces].transform_values do |ns_config|
              if ns_config[:declared_at] == :here
                # Parent declared this at its level - child inherits it
                ns_config.merge(declared_at: :inherited)
              elsif ns_config[:declared_at] == :inherited
                # Parent inherited this - child also inherits it (keep as :inherited)
                ns_config.dup
              else
                # :local_on_use - pass through unchanged
                ns_config.dup
              end
            end
            plan[:type_namespaces] = parent_plan[:type_namespaces].dup
          end

          # ==================================================================
          # PHASE 2: DECLARE OWN NAMESPACE (for non-type-only models)
          # ==================================================================
          # TYPE-ONLY MODELS: No element_name means no xmlns declarations
          # BUT we still need to plan children
          unless mapping.no_element?
            # Decide format for own namespace (only for non-type-only models)
            if effective_ns_class
              validate_namespace_class(effective_ns_class)

              # CRITICAL: Use ORIGINAL namespace class's key for lookup
              # even if we have a custom prefix override
              # This ensures adapter can find the overridden config
              key = mapping.namespace_class.to_key
              unless plan[:namespaces][key]
                # Make new declaration
                format = choose_format_with_override(mapping,
                                                     effective_ns_class, needs, options)
                xmlns_decl = build_declaration(effective_ns_class, format,
                                               options)

                plan[:namespaces][key] = {
                  ns_object: effective_ns_class, # Store effective (may be override)
                  format: format,
                  xmlns_declaration: xmlns_decl,
                  declared_at: :here,
                }
              end
            end

            # ==================================================================
            # PHASE 3: DECLARE NAMESPACE_SCOPE NAMESPACES
            # ==================================================================
            # Declare namespace_scope namespaces as prefixed (only for non-type-only models)
            # These are declared at root for descendants to use
            if needs[:namespace_scope_configs]&.any?
              needs[:namespace_scope_configs].each do |ns_config|
                ns_class = ns_config[:namespace]
                declare_mode = ns_config[:declare] || :auto

                validate_namespace_class(ns_class)

                # Skip if already in plan (by key lookup)
                key = ns_class.to_key
                next if plan[:namespaces][key]

                # Decide based on declare mode
                if declare_mode == :always
                  # Always declare, regardless of usage
                  # CRITICAL: Don't pass options - namespace_scope namespaces use their own prefix
                  plan[:namespaces][key] = {
                    ns_object: ns_class,
                    format: :prefix,
                    xmlns_declaration: build_declaration(ns_class, :prefix, {}),
                    declared_at: :here,
                  }
                elsif declare_mode == :auto
                  # Only declare if actually used (check by key)
                  if needs[:namespaces][key]
                    # CRITICAL: Don't pass options - namespace_scope namespaces use their own prefix
                    plan[:namespaces][key] = {
                      ns_object: ns_class,
                      format: :prefix,
                      xmlns_declaration: build_declaration(ns_class, :prefix,
                                                           {}),
                      declared_at: :here,
                    }
                  end
                end
              end
            end

            # ==================================================================
            # PHASE 4: DECLARE COLLECTED CHILD NAMESPACES
            # ==================================================================
            # Declare collected child element/attribute namespaces at root
            # This implements "never declare twice" - declare once at root, use everywhere
            # BUT: namespace_scope limits which namespaces are declared at root
            needs[:namespaces].each do |key, ns_data|
              ns_class = ns_data[:ns_object]
              validate_namespace_class(ns_class)

              # Skip if already declared - "never declare twice" principle
              next if plan[:namespaces][key]

              # Check if namespace is in scope (should be declared at root)
              in_scope = if needs[:namespace_scope_configs]&.any?
                           # namespace_scope is defined - check if this namespace is in it
                           needs[:namespace_scope_configs].any? do |cfg|
                             cfg[:namespace] == ns_class
                           end
                         else
                           # No namespace_scope defined - all namespaces declared at root (default)
                           true
                         end

              if in_scope
                # IN SCOPE: Declare at root level
                # CRITICAL: Only use prefix format if namespace actually has a prefix
                format = ns_class.prefix_default ? :prefix : :default

                # CRITICAL FIX: Prevent multiple default namespaces conflict
                # If this namespace has no prefix AND root already has a default namespace,
                # we MUST use prefix format (even though ns has no prefix configured)
                # This means we need to force a prefix or error
                if format == :default && !parent_plan
                  # Check if root element already declared a default namespace
                  root_ns_key = effective_ns_class&.to_key
                  if root_ns_key && plan[:namespaces][root_ns_key] && plan[:namespaces][root_ns_key][:format] == :default && (key != root_ns_key)
                    # Root already has default format, this child namespace cannot also be default
                    # Skip adding it as default - it should have been given a prefix
                    # This is a configuration error: two namespaces without prefixes
                    next # Skip non-root default namespaces
                  end
                end

                plan[:namespaces][key] = {
                  ns_object: ns_class,
                  format: format,
                  xmlns_declaration: build_declaration(ns_class, format, {}),
                  declared_at: :here,
                }
              else
                # OUT OF SCOPE: Don't declare at root, mark for local declaration
                # Local declarations always use prefix format
                plan[:namespaces][key] = {
                  ns_object: ns_class,
                  format: :prefix,
                  xmlns_declaration: build_declaration(ns_class, :prefix, {}),
                  declared_at: :local_on_use,
                }
              end
            end
          end

          # ==================================================================
          # PHASE 5: TRACK TYPE NAMESPACES
          # ==================================================================
          # Track Type namespaces from needs
          # This provides a lookup for adapters: attribute_name -> XmlNamespace CLASS
          # CRITICAL: If there's an override for a Type namespace, use the override
          # BUG FIX #2: Also add Type namespaces to plan[:namespaces] so children can inherit them
          if needs[:type_namespaces]&.any?
            needs[:type_namespaces].each do |attr_name, ns_class|
              validate_namespace_class(ns_class)
              plan[:type_namespaces][attr_name] = ns_class

              # Also add to plan[:namespaces] if not already present
              # This allows children to inherit Type namespace configurations
              key = ns_class.to_key
              unless plan[:namespaces][key]
                # Determine format (prefer prefix if namespace has one)
                format = ns_class.prefix_default ? :prefix : :default

                plan[:namespaces][key] = {
                  ns_object: ns_class,
                  format: format,
                  xmlns_declaration: build_declaration(ns_class, format, {}),
                  declared_at: :here,
                }
              end
            end
          end

          # ==================================================================
          # PHASE 6: PLAN CHILDREN RECURSIVELY
          # ==================================================================
          # Plan children
          mapping.elements.each do |elem_rule|
            # Skip if we can't resolve attributes
            next unless attributes&.any?

            attr_def = attributes[elem_rule.to]
            next unless attr_def

            child_type = attr_def.type(@register)
            next unless child_type
            next unless child_type.respond_to?(:<) &&
              child_type < Lutaml::Model::Serialize

            child_mapping = child_type.mappings_for(:xml)
            next unless child_mapping

            child_needs = needs[:children][elem_rule.to] || empty_needs

            # Pass child_type as mapper_class and inherit options (including use_prefix for custom prefixes)
            child_options = options.merge(mapper_class: child_type)

            plan[:children_plans][elem_rule.to] = plan(
              nil,
              child_mapping,
              child_needs,
              parent_plan: plan,
              options: child_options,
            )
          end

          plan
        end

        # Create declaration plan for a collection
        #
        # @param collection [Collection] the collection instance
        # @param mapping [Xml::Mapping] the XML mapping for the collection
        # @param needs [Hash] namespace needs from collector
        # @param options [Hash] serialization options
        # @return [Hash] declaration plan structure
        def plan_collection(_collection, mapping, needs, options: {})
          plan(nil, mapping, needs, parent_plan: nil, options: options)
        end

        private

        attr_reader :register

        # Validate that namespace is an XmlNamespace class
        #
        # @param ns_class [Class] the namespace class to validate
        # @raise [ArgumentError] if not a valid XmlNamespace class
        def validate_namespace_class(ns_class)
          return if ns_class.nil?

          unless ns_class.is_a?(Class) && ns_class < Lutaml::Model::XmlNamespace
            raise ArgumentError,
                  "Namespace must be XmlNamespace class, got #{ns_class.class}. " \
                  "Same URI + different prefix = different config = different class."
          end
        end

        # Build xmlns declaration string from XmlNamespace class
        #
        # @param ns_class [Class] the XmlNamespace class
        # @param format [Symbol] :default or :prefix
        # @param options [Hash] serialization options (may contain custom prefix)
        # @return [String] the xmlns declaration attribute
        def build_declaration(ns_class, format, options = {})
          # CRITICAL: If namespace has no prefix, MUST use default format
          # Using prefix format without a prefix creates invalid xmlns:=""
          if format == :prefix && !ns_class.prefix_default
            format = :default
          end

          if format == :default
            "xmlns=\"#{ns_class.uri}\""
          else
            # Use custom prefix from options if provided, otherwise use class default
            # Check options[:prefix] first for backward compatibility
            prefix = if options[:prefix].is_a?(String)
                       options[:prefix]
                     elsif options[:use_prefix].is_a?(String)
                       options[:use_prefix]
                     else
                       ns_class.prefix_default
                     end
            "xmlns:#{prefix}=\"#{ns_class.uri}\""
          end
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
        def choose_format(mapping, needs, options)
          return :default unless mapping.namespace_class

          # 1. Explicit user preference via prefix or use_prefix option
          # Check options[:prefix] first for backward compatibility
          if options.key?(:prefix)
            # options[:prefix] can be true, false, or a string
            case options[:prefix]
            when true, String
              return :prefix
            when false, nil
              return :default
            end
          elsif options.key?(:use_prefix)
            return options[:use_prefix] ? :prefix : :default
          end

          # 2. W3C rule: attributes in own namespace REQUIRE prefix
          # Check if this namespace is used for attributes (by key lookup)
          key = mapping.namespace_class.to_key
          if needs[:namespaces][key]
            ns_entry = needs[:namespaces][key]
            return :prefix if ns_entry[:used_in].include?(:attributes)
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
          # Child elements will inherit the default namespace automatically
          :default
        end

        # Choose format for namespace declaration with custom namespace class override
        #
        # Similar to choose_format but accepts an effective namespace class parameter
        # to support custom prefix overrides via options[:prefix]
        #
        # @param mapping [Xml::Mapping] the element mapping
        # @param effective_ns_class [Class] the effective namespace class (may be override)
        # @param needs [Hash] namespace needs (with string keys)
        # @param options [Hash] serialization options
        # @return [Symbol] :default or :prefix
        def choose_format_with_override(mapping, effective_ns_class, needs,
options)
          return :default unless effective_ns_class

          # 1. Explicit user preference via prefix or use_prefix option
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

          # 2. W3C rule: attributes in own namespace REQUIRE prefix
          key = effective_ns_class.to_key
          if needs[:namespaces][key]
            ns_entry = needs[:namespaces][key]
            return :prefix if ns_entry[:used_in].include?(:attributes)
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

          # 4. Default: prefer default namespace (cleaner, no prefix needed)
          :default
        end

        # Return empty plan structure for type-only models
        #
        # @return [Hash] empty declaration plan
        def empty_plan
          {
            namespaces: {},
            children_plans: {},
            type_namespaces: {},
          }
        end

        # Return empty needs structure (used when child needs not found)
        #
        # @return [Hash] empty needs structure
        def empty_needs
          {
            namespaces: {},
            children: {},
            type_namespaces: {},
          }
        end
      end
    end
  end
end
