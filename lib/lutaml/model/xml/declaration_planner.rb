# frozen_string_literal: true

require_relative "declaration_plan"
require_relative "namespace_declaration"

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
        # THREE-TIER PRIORITY SYSTEM (Issue #3):
        # Tier 1: Input namespaces (from parsed XML) - ALWAYS preserved
        # Tier 2: namespace_scope :always declarations
        # Tier 3: Used namespaces + namespace_scope :auto (if used)
        #
        # @param element [Object] the model instance (can be nil for type analysis)
        # @param mapping [Xml::Mapping] the XML mapping for this element
        # @param needs [Hash] namespace needs from collector (with string keys)
        # @param parent_plan [DeclarationPlan, nil] parent element's plan
        # @param options [Hash] serialization options (may include :input_namespaces)
        # @return [DeclarationPlan] declaration plan structure
        def plan(element, mapping, needs, parent_plan: nil, options: {})
          plan = DeclarationPlan.new

          # ==================================================================
          # TIER 1: PRE-FILL WITH INPUT NAMESPACES (Highest Priority)
          # ==================================================================
          # Input namespaces from parsed XML are ALWAYS preserved exactly
          # This prevents Issue #3A (losing unused namespaces like xmlns:xsi)
          # Only apply at root level (no parent_plan) AND only when input_namespaces provided
          if !parent_plan && options[:input_namespaces]&.any?
            prefill_input_namespaces(plan, options[:input_namespaces])
          end

          # Get mapper_class and attributes early for Type namespace lookups
          mapper_class = element&.class || options[:mapper_class]

          # Extract custom prefix override from options (if provided)
          # This will be passed through to namespace declarations instead of creating anonymous classes
          custom_prefix = nil
          custom_prefix = options[:prefix] if options[:prefix].is_a?(String)
          custom_prefix ||= options[:use_prefix] if options[:use_prefix].is_a?(String)

          # Prevent infinite recursion for type analysis (when element is nil)
          if element.nil? && mapper_class
            if @visited_types.include?(mapper_class)
              # CRITICAL FIX FOR BUG #3:
              # When we've already visited this type, return early to prevent infinite recursion.
              # BUT: if we have a parent_plan, we must inherit its namespaces!
              # Otherwise, deeply nested structures lose namespace configuration.
              if parent_plan
                # Inherit parent's namespaces
                inherited_plan = DeclarationPlan.new
                inherited_plan.inherit_from(parent_plan)
                return inherited_plan
              else
                return DeclarationPlan.empty
              end
            end

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
            plan.inherit_from(parent_plan)
          end

          # ==================================================================
          # PHASE 2: DECLARE OWN NAMESPACE (for non-type-only models)
          # ==================================================================
          # TYPE-ONLY MODELS: No element_name means no xmlns declarations
          # BUT we still need to plan children
          unless mapping.no_element?
           # CRITICAL FIX #1: Elements WITHOUT namespace identity cannot declare xmlns
            # Architecture Principle (line 89-91): "if an element does not declare any namespace itself,
            # it cannot set any default namespace, but it can hoist namespaces with prefixes"
            #
            # When mapping.namespace_class is nil, the element has NO namespace identity.
            # It inherits parent's default namespace automatically per W3C rules.
            # Skip declaration logic and proceed to PHASE 3/4/5/6.
            unless mapping.namespace_class.nil?
              validate_namespace_class(mapping.namespace_class)

              # Use original namespace class (no override needed - prefix override travels with declaration)
              ns_class = mapping.namespace_class

              # CRITICAL: Use namespace class's key for lookup
              key = ns_class.to_key
              existing = plan.namespace(key)

              # NAMESPACE INHERITANCE RULE:
              # If parent declared this namespace with PREFIX → child MUST use PREFIX too
              # This prevents declaring the same namespace twice in the tree
              # Only re-evaluate format if: no existing, local_on_use, or inherited as DEFAULT
              if !existing || existing.local_on_use?
                # No existing or marked for local - make new declaration
                format = choose_format_with_override(mapping,
                                                     ns_class, needs, options)

                # CRITICAL FIX: Local namespace declarations (not in parent's scope)
                # MUST use prefix format to avoid conflicting with parent's default namespace.
                # If we have a parent and our namespace is NOT in parent's plan,
                # we're declaring locally - force prefix format.
                # ALSO: if parent has namespace marked as :local_on_use, we must declare locally with prefix
                if parent_plan && (!parent_plan.namespace(key) || parent_plan.namespace(key)&.local_on_use?)
                  # Local declaration - check if it's the element's own namespace
                  # ARCHITECTURAL PRINCIPLE: Element CAN declare its OWN namespace as default,
                  # even when parent doesn't have it in scope. Only CHILD/DIFFERENT namespaces
                  # must use prefix when declaring locally.
                  is_own_namespace = ns_class == mapping.namespace_class

                  # CRITICAL FIX: Only force prefix for DIFFERENT namespaces (not own)
                  # Own namespace can use default format per W3C semantics - xmlns="uri" shadows parent
                  # The prefix_default configuration is for when prefix IS needed, not a requirement
                  # Let choose_format_with_override decide based on W3C rules (attributes, etc.)
                  if !is_own_namespace
                    # Different namespace - MUST use prefix to avoid conflict
                    format = :prefix
                  end
                  # else: Own namespace - use format from choose_format_with_override
                  # This allows default format unless W3C rules require prefix
                end

                xmlns_decl = build_declaration(ns_class, format, options)

                plan.add_namespace(
                  ns_class,
                  format: format,
                  xmlns_declaration: xmlns_decl,
                  declared_at: :here,
                  prefix_override: custom_prefix
                )
              elsif existing.inherited?
                # CRITICAL FIX #2: PREFIX INHERITANCE
                # Parent declared this namespace - check if we must preserve PREFIX format
                # Architecture Principle (line 102-114): "If a namespace is hoisted as prefix,
                # all elements in that namespace should also utilize the same prefix"
                if existing.prefix_format?
                  # Parent used PREFIX format → child MUST preserve it
                  # Do NOT re-evaluate format - this would break prefix inheritance
                  plan.add_namespace(
                  ns_class,
                    format: existing.format,
                    xmlns_declaration: existing.xmlns_declaration,
                    declared_at: existing.declared_at.to_sym,  # Keep as inherited
                    prefix_override: custom_prefix  # Propagate custom prefix if present
                  )
                else
                  # Parent used DEFAULT format - check if we need to redeclare
                  must_redeclare = false
                  if parent_plan
                    # Check if parent_plan has a different default namespace
                    parent_default_decl = parent_plan.declarations_here.values.find(&:default_format?)
                    if parent_default_decl && parent_default_decl.uri != ns_class.uri
                      # Parent uses different default namespace - we MUST redeclare
                      must_redeclare = true
                    end
                  end

                  if must_redeclare
                    # Redeclare because parent changed the default namespace
                    format = choose_format_with_override(mapping,
                                                         ns_class, needs, options)
                    xmlns_decl = build_declaration(ns_class, format, options)

                    plan.add_namespace(
                      ns_class,
                      format: format,
                      xmlns_declaration: xmlns_decl,
                      declared_at: :here,  # Must declare here, not inherited
                      prefix_override: custom_prefix
                    )
                  else
                    # Parent used default and we can inherit → keep as inherited
                    format = choose_format_with_override(mapping,
                                                         ns_class, needs, options)
                    xmlns_decl = build_declaration(ns_class, format, options)

                    plan.add_namespace(
                      ns_class,
                      format: format,
                      xmlns_declaration: xmlns_decl,
                      declared_at: :inherited,  # Keep as inherited
                      prefix_override: custom_prefix
                    )
                  end
                end
              end
            end
            # If mapping.namespace_class is nil, we skip all declaration logic above
            # and continue to PHASE 3/4/5/6
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
              next if plan.namespace?(key)

              # Decide based on declare mode
              if declare_mode == :always
                # Always declare, regardless of usage
                # CRITICAL: Don't pass options - namespace_scope namespaces use their own prefix
                plan.add_namespace(
                  ns_class,
                  format: :prefix,
                  xmlns_declaration: build_declaration(ns_class, :prefix, {}),
                  declared_at: :here
                )
              elsif declare_mode == :auto
                # Only declare if actually used (check by key)
                if needs[:namespaces][key]
                  # CRITICAL: Don't pass options - namespace_scope namespaces use their own prefix
                  plan.add_namespace(
                    ns_class,
                    format: :prefix,
                    xmlns_declaration: build_declaration(ns_class, :prefix, {}),
                    declared_at: :here
                  )
                end
              end
            end
          end

          # ==================================================================
          # PHASE 4: DECLARE COLLECTED CHILD NAMESPACES
          # ==================================================================
          # CRITICAL FIX FOR NAMESPACE BLEEDING:
          # Child elements with DIFFERENT namespaces should declare locally,
          # not hoist to parent. Only these should hoist to root:
          # 1. Element's own namespace (already in plan from PHASE 2)
          # 2. namespace_scope namespaces (already in plan from PHASE 3)
          # 3. Namespaces explicitly in namespace_scope with declare: :auto
          #
          # All other child namespaces should be marked :local_on_use
          #
          # CRITICAL FIX FOR TYPE NAMESPACES:
          # Type namespaces should NOT be processed here - they are handled
          # in PHASE 5 where namespace_scope logic is correctly applied.
          # Skip any namespace that appears in needs[:type_namespaces]
          needs[:namespaces].each do |key, ns_data|
            ns_class = ns_data[:ns_object]
            validate_namespace_class(ns_class)

            # Skip if already declared - "never declare twice" principle
            next if plan.namespace?(key)

            # CRITICAL FIX: Skip Type namespaces - they're handled in PHASE 5
            # Type namespaces need special namespace_scope awareness
            is_type_namespace = needs[:type_namespace_classes]&.include?(ns_class)
            next if is_type_namespace

            # CRITICAL FIX: Check if this namespace should be in scope
            # Per three-phase architecture (Phase 2: Declaration Planning):
            # A node can hoist a namespace if it is ELIGIBLE:
            # 1. Node belongs to that namespace (can hoist as default or prefix)
            # 2. Node has namespace_scope for that namespace (can hoist as prefix)
            #
            # If node is not eligible, leave to descendants to hoist locally
            in_scope = if needs[:namespace_scope_configs]&.any?
                         # Tier 1: namespace_scope is defined - check if this namespace is in it
                         needs[:namespace_scope_configs].any? do |cfg|
                           cfg[:namespace] == ns_class
                         end
                       elsif mapping.namespace_class == ns_class
                         # Tier 2: Element belongs to this namespace → eligible to hoist
                         # This covers the element's own namespace
                         true
                       else
                         # Tier 3: NOT eligible → mark local_on_use
                         # Descendants will declare locally (namespace scope minimization)
                         # This enforces: namespaces declared close to usage unless namespace_scope
                         false
                       end

            if in_scope
              # IN SCOPE: Declare at root level (from namespace_scope)
              # CRITICAL: Only use prefix format if namespace actually has a prefix
              format = :default

              # CRITICAL FIX: Prevent multiple default namespaces conflict
              # If this namespace has no prefix AND root already has a default namespace,
              # we MUST use prefix format (even though ns has no prefix configured)
              # This means we need to force a prefix or error
              if format == :default && !parent_plan
                # Check if root element already declared a default namespace
                effective_ns_class = namespace_class_override || mapping.namespace_class
                root_ns_key = effective_ns_class&.to_key
                root_ns_decl = plan.namespace(root_ns_key)
                if root_ns_key && root_ns_decl&.default_format? && (key != root_ns_key)
                  # Root already has default format, this child namespace cannot also be default
                  # Skip adding it as default - it should have been given a prefix
                  # This is a configuration error: two namespaces without prefixes
                  next # Skip non-root default namespaces
                end
              end

              plan.add_namespace(
                ns_class,
                format: format,
                xmlns_declaration: build_declaration(ns_class, format, {}),
                declared_at: :here
              )
            else
              # OUT OF SCOPE: Don't declare at root, mark for local declaration
              # Local declarations always use prefix format
              plan.add_namespace(
                ns_class,
                format: :prefix,
                xmlns_declaration: build_declaration(ns_class, :prefix, {}),
                declared_at: :local_on_use
              )
            end
          end

          # ==================================================================
          # PHASE 5: TRACK TYPE NAMESPACES
          # ==================================================================
          # Track Type namespaces from needs
          # This provides a lookup for adapters: attribute_name -> XmlNamespace CLASS
          # CRITICAL: Type namespaces respect namespace_scope like regular namespaces
          # - If in namespace_scope: hoist to this element (:here)
          # - If NOT in namespace_scope: declare locally on each element (:local_on_use)
          if needs[:type_namespaces]&.any?
            needs[:type_namespaces].each do |attr_name, ns_class|
              validate_namespace_class(ns_class)
              plan.add_type_namespace(attr_name, ns_class)

              # Skip if already in plan (already handled in earlier phases)
              key = ns_class.to_key
              next if plan.namespace?(key)

              # Check if Type namespace is in namespace_scope
              in_scope = if needs[:namespace_scope_configs]&.any?
                          # namespace_scope is defined - check if this Type namespace is in it
                          needs[:namespace_scope_configs].any? do |cfg|
                            cfg[:namespace] == ns_class
                          end
                        else
                          # No namespace_scope - Type namespaces hoist by default
                          true
                        end

              if in_scope
                # IN SCOPE: Hoist Type namespace to this element
                # CRITICAL FIX: Type element namespaces should use prefix format by default
                # Only allow default format if Type namespace IS the element's own namespace
                format = :prefix

                # EXCEPTION: If Type namespace IS element's own namespace, allow default format
                # This handles the case where element and Type share the same namespace
                if mapping.namespace_class && mapping.namespace_class == ns_class
                  format = :default
                end

                # CRITICAL: XML attribute Type namespaces MUST use prefix format
                # W3C rule: attributes cannot be in default namespace
                if needs[:type_attribute_namespaces]&.include?(ns_class)
                  format = :prefix
                end

                # CRITICAL FIX: If parent already declared this namespace, inherit its format
                # This ensures Type namespaces respect parent's format choice
                # Architecture Principle: "If a namespace is hoisted as prefix,
                # all elements in that namespace should also utilize the same prefix"
                existing_in_parent = parent_plan&.namespace(key)
                if existing_in_parent
                  # Parent already has this namespace - inherit its format
                  format = existing_in_parent.format
                end

                plan.add_namespace(
                  ns_class,
                  format: format,
                  xmlns_declaration: build_declaration(ns_class, format, {}),
                  declared_at: :here
                )
              else
                # OUT OF SCOPE: Type namespace declares locally on each element
                # Local declarations always use prefix format
                plan.add_namespace(
                  ns_class,
                  format: :prefix,
                  xmlns_declaration: build_declaration(ns_class, :prefix, {}),
                  declared_at: :local_on_use
                )
              end
            end
          end

          # ==================================================================
          # PHASE 5.5: DETERMINE ELEMENT NAMESPACE STRATEGIES
          # ==================================================================
          # For each element, create a namespace resolution strategy that
          # encapsulates the decision of which namespace to use.
          # This moves decision logic OUT of adapter and INTO planner.
          determine_element_strategies(mapping, needs, plan, attributes) if attributes&.any?

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

            # Pass child_type as mapper_class
            # CRITICAL FIX: Only pass use_prefix to children with SAME namespace as parent
            # Children with different namespaces should use their own namespace's prefix
            #
            # SPECIAL CASE: W3C reserved namespaces (xml:, xsi:, xs:) always use their
            # reserved prefix regardless of parent's prefix settings
            child_ns_class = child_mapping&.namespace_class

            child_options = if w3c_namespace?(child_ns_class)
                              # W3C namespace - always use reserved prefix, pass through
                              options.merge(mapper_class: child_type)
                            elsif child_ns_class == mapping.namespace_class
                              # Same namespace as parent - inherit parent's prefix choice
                              options.merge(mapper_class: child_type)
                            else
                              # Different namespace - child makes its own format decision
                              # Don't pass prefix options so child can apply W3C rules
                              options.slice(:mapper_class, :input_namespaces).merge(
                                mapper_class: child_type
                              )
                            end

            child_plan = plan(
              nil,
              child_mapping,
              child_needs,
              parent_plan: plan,
              options: child_options
            )

            plan.add_child_plan(elem_rule.to, child_plan)
          end

          plan
        end

        # Create declaration plan for a collection
        #
        # @param collection [Collection] the collection instance
        # @param mapping [Xml::Mapping] the XML mapping for the collection
        # @param needs [Hash] namespace needs from collector
        # @param options [Hash] serialization options
        # @return [DeclarationPlan] declaration plan structure
        def plan_collection(_collection, mapping, needs, options: {})
          plan(nil, mapping, needs, parent_plan: nil, options: options)
        end

        private

        attr_reader :register

        # Pre-fill plan with input namespaces from parsed XML
        #
        # This implements Tier 1 priority: Input namespaces are always preserved
        # exactly as they appeared in the input, regardless of usage.
        #
        # @param plan [DeclarationPlan] the plan to pre-fill
        # @param input_ns [Hash] map of prefix => {uri:, prefix:} from parsed XML
        def prefill_input_namespaces(plan, input_ns)
          return unless input_ns&.any?

          input_ns.each do |prefix_key, ns_config|
            # Create an XmlNamespace class for this input namespace
            # We need a consistent key for lookup, so we'll use URI as the key
            uri = ns_config[:uri]
            prefix = ns_config[:prefix]

            # Determine format based on whether it has a prefix
            format = prefix_key == :default ? :default : :prefix

            # Build xmlns declaration string
            xmlns_decl = if format == :default
                          "xmlns=\"#{uri}\""
                        else
                          "xmlns:#{prefix}=\"#{uri}\""
                        end

            # Try to find existing XmlNamespace class with this URI
            # If not found, create anonymous class for input namespace
            ns_class = find_or_create_namespace_class(uri, prefix)

            # Add to plan with :input source marker
            plan.add_namespace(
              ns_class,
              format: format,
              xmlns_declaration: xmlns_decl,
              declared_at: :here,
              source: :input  # Mark as from input XML
            )
          end
        end

        # Find existing XmlNamespace class by URI or create anonymous one
        #
        # @param uri [String] the namespace URI
        # @param prefix [String, nil] the namespace prefix
        # @return [Class] XmlNamespace class
        def find_or_create_namespace_class(uri, prefix)
          # Create anonymous class for input namespace
          # Use class instance variable to ensure consistent to_key
          # The class will be garbage collected after serialization completes
          klass = Class.new(Lutaml::Model::XmlNamespace) do
            # Use send to set class methods on the anonymous class
            define_singleton_method(:uri) { uri }
            define_singleton_method(:prefix_default) { prefix }
          end

          # Call the DSL methods to set values properly
          klass.uri(uri)
          klass.prefix_default(prefix) if prefix

          klass
        end

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

          # 2. W3C rule: Attributes in SAME namespace require prefix
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

          # 4. Default: prefer default namespace (cleaner, no prefix needed)
          :default
        end

        # Return empty plan structure for type-only models
        #
        # @return [DeclarationPlan] empty declaration plan
        def empty_plan
          DeclarationPlan.empty
        end

        # Check if namespace is a W3C reserved namespace
        #
        # W3C reserved namespaces have special semantics and fixed prefixes:
        # - xml: http://www.w3.org/XML/1998/namespace (xml:lang, xml:space)
        # - xsi: http://www.w3.org/2001/XMLSchema-instance (xsi:nil, xsi:type)
        # - xs: http://www.w3.org/2001/XMLSchema (XSD types)
        #
        # @param ns_class [Class, nil] XmlNamespace class
        # @return [Boolean] true if W3C reserved namespace
        def w3c_namespace?(ns_class)
          return false unless ns_class

          w3c_uris = [
            "http://www.w3.org/XML/1998/namespace",           # xml:
            "http://www.w3.org/2001/XMLSchema-instance",       # xsi:
            "http://www.w3.org/2001/XMLSchema",                # xs:
          ]

          w3c_uris.include?(ns_class.uri)
        end

        # Return empty needs structure (used when child needs not found)
        #
        # @return [Hash] empty needs structure
        def empty_needs
          {
            namespaces: {},
            children: {},
            type_namespaces: {},
            type_namespace_classes: Set.new,
            type_attribute_namespaces: Set.new,
            type_element_namespaces: Set.new,
          }
        end

        # Determine namespace resolution strategies for elements
        #
        # For each element mapping, creates a strategy that encapsulates
        # the namespace decision logic. This moves decision logic from adapter
        # to planner, ensuring single source of truth.
        #
        # @param mapping [Xml::Mapping] the element mapping
        # @param needs [Hash] namespace needs from collector
        # @param plan [DeclarationPlan] the declaration plan
        # @param attributes [Hash] attribute definitions
        # @return [void]
        def determine_element_strategies(mapping, needs, plan, attributes)
          mapping.elements.each do |element_rule|
            attr_def = attributes[element_rule.to]
            next unless attr_def

            strategy = create_strategy_for_element(
              element_rule,
              attr_def,
              mapping,
              plan,
              needs
            )

            plan.set_element_strategy(element_rule.to, strategy) if strategy
          end
        end

        # Create appropriate namespace resolution strategy for an element
        #
        # Priority order (MECE):
        # 1. Explicit directives (qualified?, unqualified?, prefix_set?, namespace: :inherit)
        # 2. Type namespace (if Type has xml_namespace)
        # 3. Parent namespace (if qualified element)
        # 4. Blank namespace (default)
        #
        # @param rule [Xml::MappingRule] the element mapping rule
        # @param attr_def [Attribute] the attribute definition
        # @param mapping [Xml::Mapping] the parent mapping
        # @param plan [DeclarationPlan] the declaration plan
        # @param needs [Hash] namespace needs
        # @return [NamespaceResolutionStrategy, nil] the strategy
        def create_strategy_for_element(rule, attr_def, mapping, plan, needs)
          # Priority 1: Explicit namespace directives
          if rule.namespace_param == :inherit
            parent_ns_class = mapping.namespace_class
            return nil unless parent_ns_class

            parent_ns_decl = plan.namespace_for_class(parent_ns_class)
            return InheritedNamespaceStrategy.new(parent_ns_decl) if parent_ns_decl
          end

          if rule.qualified? || rule.unqualified?
            ns_class = rule.namespace_class || mapping.namespace_class
            return nil unless ns_class

            ns_decl = plan.namespace_for_class(ns_class)
            return ExplicitNamespaceStrategy.new(ns_decl, rule) if ns_decl
          end

          # Priority 2: Type namespace
          type_ns_class = plan.type_namespace(rule.to)
          if type_ns_class
            # Get the actual type class to check if it has xml_namespace
            type_class = attr_def.type(@register)

            # CRITICAL: Check if Type HAS xml_namespace
            if type_class&.respond_to?(:xml_namespace) && type_class.xml_namespace
              # Type has explicit namespace - use TypeNamespaceStrategy
              type_ns_decl = plan.namespace(type_ns_class.to_key)
              return TypeNamespaceStrategy.new(type_ns_decl, type_class) if type_ns_decl
            end
            # If native type WITHOUT xml_namespace, fall through to Priority 3
          end

          # Priority 3: Parent namespace (qualified elements)
          # Use Strategy pattern from XmlNamespace to determine inheritance
          # W3C elementFormDefault controls whether children inherit parent namespace
          if !rule.namespace_set? && mapping.namespace_class
            parent_ns_decl = plan.namespace_for_class(mapping.namespace_class)

            if parent_ns_decl
              # Get inheritance strategy from parent namespace class
              strategy = mapping.namespace_class.inheritance_strategy

              # Determine element type for strategy decision
              type_class = attr_def.type(@register)
              element_type = if type_class.respond_to?(:<) && type_class < Lutaml::Model::Serialize
                               :model
                             else
                               :native_value
                             end

              # Delegate inheritance decision to strategy
              if strategy.inherits?(
                element_type: element_type,
                parent_ns_decl: parent_ns_decl,
                mapping: mapping
              )
                # Strategy says child inherits parent namespace
                return SchemaQualifiedStrategy.new(parent_ns_decl)
              end
              # else: Strategy says don't inherit, fall through to blank namespace (Priority 4)
            end
          end

          # Priority 4: Blank namespace (default)
          # W3C Compliance: Blank namespace elements (namespace: nil) or
          # unqualified children of prefixed namespaces end up here
          parent_uses_default = false
          if mapping.namespace_class
            parent_ns_decl = plan.namespace_for_class(mapping.namespace_class)
            parent_uses_default = parent_ns_decl&.default_format? || false
          end

          BlankNamespaceStrategy.new(parent_uses_default: parent_uses_default)
        end
      end
    end
  end
end
