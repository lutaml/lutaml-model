# frozen_string_literal: true

require_relative "declaration_plan"
require_relative "namespace_declaration"
require_relative "namespace_needs"
require_relative "namespace_usage"
require_relative "decisions/element_prefix_resolver"

module Lutaml
  module Model
    module Xml
      # Phase 2: Declaration Planning
      #
      # Builds ElementNode tree with W3C-compliant attribute prefix decisions.
      # The tree is isomorphic to XmlDataModel for index-based parallel traversal.
      #
      # CRITICAL: This planner ONLY builds trees. NO flat mode.
      #
      class DeclarationPlanner
        # Initialize planner with register for type resolution
        #
        # @param register [Symbol] the register ID for type resolution
        def initialize(register = nil)
          @register = register || Lutaml::Model::Config.default_register
        end

        # Create declaration plan tree for XmlElement
        #
        # @param root_element [XmlDataModel::XmlElement, Model, nil, Class] root element, model instance, or nil/Class for unit testing
        # @param mapping [Xml::Mapping] the XML mapping
        # @param needs [NamespaceNeeds] namespace needs from collector
        # @param options [Hash] serialization options (may contain :__stored_plan with input_formats)
        # @return [DeclarationPlan] declaration plan with tree structure
        def plan(root_element, mapping, needs, parent_plan: nil, options: {},
visited_types: Set.new)
          # Normalize root_element: transform Model instances to XmlElement
          root_element = normalize_root_element(root_element, mapping, options)

          # Allow nil and Class for unit testing (type analysis without element instance)
          if root_element && !root_element.is_a?(Lutaml::Model::XmlDataModel::XmlElement) && !root_element.is_a?(Class)
            raise ArgumentError,
                  "DeclarationPlanner ONLY works with XmlElement trees. Got: #{root_element.class}"
          end

          # Handle nil or Class root_element for unit testing
          if root_element.nil? || root_element.is_a?(Class)
            require_relative "type_namespace_resolver"

            # CRITICAL: Resolve type namespace refs BEFORE using type_attribute_namespaces
            TypeNamespaceResolver.new(@register).resolve(needs)

            # Build namespace_classes hash from needs for unit testing
            namespace_classes = {}
            needs.all_namespace_classes.each do |ns_class|
              namespace_classes[ns_class.uri] = ns_class
            end

            # CRITICAL: Add namespace_scope namespaces to namespace_classes
            # (even if not used, :always mode requires them to be declared)
            needs.namespace_scope_configs.each do |scope_config|
              ns_class = scope_config.namespace_class
              namespace_classes[ns_class.uri] ||= ns_class
            end

            # Get element's own namespace (from mapping)
            element_namespace = mapping&.namespace_class

            # Create minimal root node with namespace hoisting info
            # W3C rule: Namespaces used in attributes MUST use prefix format
            hoisted = {}

            # FIRST: Process namespace_scope configurations (root-only)
            needs.namespace_scope_configs.each do |scope_config|
              ns_class = scope_config.namespace_class
              next if ns_class == element_namespace # Don't add root's own namespace here

              # Check :always mode or :auto mode with usage
              ns_usage = needs.namespace(ns_class.to_key)
              should_declare = scope_config.always_mode? ||
                (scope_config.auto_mode? && ns_usage&.used_in&.any?)

              if should_declare
                prefix = ns_class.prefix_default || "ns#{hoisted.keys.length}"
                hoisted[prefix] = ns_class.uri
              end
            end

            # SECOND: Add element's own namespace (if not already added)
            if element_namespace && !hoisted.value?(element_namespace.uri)
              # Check if element's namespace is used in type attributes
              # If so, use prefix format (W3C rule: namespaces in attributes MUST use prefix)
              element_ns_in_attributes = needs.type_attribute_namespaces.any? do |ns|
                ns.uri == element_namespace.uri
              end

              # Check use_prefix option (Tier 1 priority)
              use_prefix_option = options[:use_prefix]

              if element_ns_in_attributes
                # Namespace used in attributes - MUST use prefix format
                prefix = element_namespace.prefix_default || "ns#{hoisted.keys.length}"
                hoisted[prefix] = element_namespace.uri
              elsif use_prefix_option == true
                # Force prefix format when use_prefix: true
                prefix = element_namespace.prefix_default || "ns#{hoisted.keys.length}"
                hoisted[prefix] = element_namespace.uri
              elsif use_prefix_option.is_a?(String)
                # Use custom prefix string
                hoisted[use_prefix_option] = element_namespace.uri
              elsif use_prefix_option == false
                # Force default format when use_prefix: false
                hoisted[nil] = element_namespace.uri
              else
                # Default: prefer default format (cleaner)
                hoisted[nil] = element_namespace.uri
              end
            end

            # THIRD: Add type namespaces (W3C: type namespaces MUST use prefix)
            # CRITICAL: Type namespaces respect namespace_scope directive.
            # When namespace_scope is configured, only hoist type namespaces in scope.
            #
            # Check if namespace_scope is configured
            has_namespace_scope = !needs.namespace_scope_configs.empty?

            # Type attribute namespaces
            needs.type_attribute_namespaces.each do |ns_class|
              ns_uri = ns_class.uri
              next if hoisted.value?(ns_uri) # Skip if already added

              # If namespace_scope is configured, only hoist if in scope
              if has_namespace_scope
                scope_config = needs.scope_config_for(ns_class)
                next unless scope_config
              end

              # Namespaces in attributes MUST use prefix format (W3C rule)
              prefix = ns_class.prefix_default || "ns#{hoisted.keys.length}"
              hoisted[prefix] = ns_class.uri
            end

            # Type element namespaces
            needs.type_element_namespaces.each do |ns_class|
              ns_uri = ns_class.uri
              next if hoisted.value?(ns_uri) # Skip if already added
              next if ns_class == element_namespace # Skip element's own namespace

              # NOTE: Type namespaces are different from child element namespaces.
              # Type namespaces are declared on Type::Value subclasses and used as
              # prefixes on child elements. They MUST be hoisted to root with prefix
              # format (W3C constraint: only one default namespace per element).
              #
              # The condition below only applies to child element namespaces, NOT Type
              # namespaces. Type namespaces should ALWAYS be hoisted.
              #
              # Examples of child element namespaces (should NOT be hoisted if different):
              # - Root has XMI namespace, child has XMI_NEW namespace → child declares
              # - Root has NO namespace, child has XMI namespace → child declares
              #
              # Examples of Type namespaces (should ALWAYS be hoisted):
              # - Root has any namespace, attribute type has XMI namespace → hoist XMI
              # - Root has NO namespace, attribute type has XMI namespace → hoist XMI
              # Type namespaces are NOT about element structure, they're about type identity.

              # If namespace_scope is configured, only hoist if in scope
              if has_namespace_scope
                scope_config = needs.scope_config_for(ns_class)
                next unless scope_config
              end

              # Type element namespaces MUST use prefix format
              prefix = ns_class.prefix_default || "ns#{hoisted.keys.length}"
              hoisted[prefix] = ns_class.uri
            end

            # FOURTH: Add remaining namespaces not in namespace_scope
            needs.all_namespace_classes.each do |ns_class|
              ns_uri = ns_class.uri
              next if hoisted.value?(ns_uri) # Skip if already added

              # Check if this namespace is in namespace_scope (skip if yes)
              scope_config = needs.scope_config_for(ns_class)
              next if scope_config

              # Add remaining namespace (default format preferred)
              hoisted[nil] = ns_class.uri
            end

            root_node = DeclarationPlan::ElementNode.new(
              qualified_name: "",
              use_prefix: nil,
              hoisted_declarations: hoisted,
            )

            # Build children_plans for attributes with Serializable types
            children_plans = build_children_plans_from_metadata(mapping, needs,
                                                                options)

            return DeclarationPlan.new(
              root_node: root_node,
              global_prefix_registry: build_prefix_registry(needs),
              input_formats: {},
              namespace_classes: namespace_classes,
              children_plans: children_plans,
            )
          end

          # TREE PATH: XmlElement tree path
          # CRITICAL: Resolve type namespace refs BEFORE using type_attribute_namespaces
          require_relative "type_namespace_resolver"
          TypeNamespaceResolver.new(@register).resolve(needs)

          # Extract input_formats from stored plan if present (format preservation)
          input_formats = options[:__stored_plan]&.input_formats || {}
          build_options = options.merge(input_formats: input_formats)

          # Build namespace_classes hash for unit testing compatibility
          namespace_classes = {}
          needs.all_namespace_classes.each do |ns_class|
            namespace_classes[ns_class.uri] = ns_class
          end

          # Build the element node tree recursively (mark root, no parent context)
          root_node = build_element_node(
            root_element, mapping, needs, build_options,
            is_root: true,
            parent_format: nil,
            parent_namespace_class: nil,
            parent_hoisted: {}
          )

          # Build children_plans for each child element (for child_plan() method)
          children_plans = build_children_plans(root_element, mapping, needs,
                                                build_options)

          # Create DeclarationPlan with tree and input_formats
          DeclarationPlan.new(
            root_node: root_node,
            global_prefix_registry: build_prefix_registry(needs),
            input_formats: input_formats,
            namespace_classes: namespace_classes,
            children_plans: children_plans,
          )
        end

        # Create declaration plan for a collection
        #
        # @param collection [Collection] the collection object
        # @param mapping [Xml::Mapping] the XML mapping
        # @param needs [NamespaceNeeds] namespace needs from collector
        # @return [DeclarationPlan] declaration plan with children_plans
        def plan_collection(_collection, mapping, needs)
          # For collections, create a plan with children_plans for each item
          root_node = DeclarationPlan::ElementNode.new(
            qualified_name: mapping.root_element || "",
            use_prefix: nil,
            hoisted_declarations: {},
          )

          # Build namespace_classes from needs
          namespace_classes = {}
          needs.all_namespace_classes.each do |ns_class|
            namespace_classes[ns_class.uri] = ns_class
          end

          # TODO: Build individual child plans for collection items
          # For now, return empty children_plans
          children_plans = {}

          DeclarationPlan.new(
            root_node: root_node,
            global_prefix_registry: build_prefix_registry(needs),
            input_formats: {},
            namespace_classes: namespace_classes,
            children_plans: children_plans,
          )
        end

        private

        attr_reader :register

        # Normalize root element: transform Model instances to XmlElement
        #
        # @param root_element [XmlDataModel::XmlElement, Model, nil, Class] Root element
        # @param mapping [Xml::Mapping] XML mapping
        # @param options [Hash] Serialization options
        # @return [XmlDataModel::XmlElement, nil, Class] Normalized root element
        def normalize_root_element(root_element, _mapping, options)
          return root_element if root_element.nil? || root_element.is_a?(Class)
          return root_element if root_element.is_a?(Lutaml::Model::XmlDataModel::XmlElement)

          # Check if root_element is a Model instance (has xml mapping)
          if root_element.is_a?(Lutaml::Model::Serialize)
            require_relative "transformation"

            # Get mapper_class from options or infer from root_element
            mapper_class = options[:mapper_class] || root_element.class

            # Get mapping for the model class
            mapping_dsl = mapper_class.mappings_for(:xml, @register)

            # Get the Register object (not just the ID)
            register_obj = Lutaml::Model::GlobalRegister.lookup(@register) if @register

            # Use Xml::Transformation to convert model to XmlElement
            transformation = Xml::Transformation.new(mapper_class, mapping_dsl,
                                                     :xml, register_obj)
            transformed = transformation.transform(root_element, options)

            # Return transformed XmlElement
            return transformed if transformed.is_a?(Lutaml::Model::XmlDataModel::XmlElement)
          end

          # Return as-is if no transformation needed
          root_element
        end

        # Build children_plans hash for child_plan() method
        #
        # @param xml_element [XmlDataModel::XmlElement] Parent element
        # @param mapping [Xml::Mapping] XML mapping
        # @param needs [NamespaceNeeds] Namespace needs
        # @param options [Hash] Serialization options
        # @return [Hash<Symbol, DeclarationPlan>] Children plans by attribute name
        def build_children_plans(xml_element, mapping, needs, options)
          children_plans = {}

          # Get mapper_class to find child attributes
          mapper_class = options[:mapper_class]
          return children_plans unless mapper_class.respond_to?(:attributes)

          # Build namespace_classes hash for child plans
          namespace_classes = {}
          needs.all_namespace_classes.each do |ns_class|
            namespace_classes[ns_class.uri] = ns_class
          end

          # Iterate through XmlElement children
          xml_element.children.each do |xml_child|
            next unless xml_child.is_a?(Lutaml::Model::XmlDataModel::XmlElement)

            # Find the matching mapping rule for this child
            child_name = xml_child.name
            matching_rule = mapping.elements.find do |rule|
              rule.name.to_s == child_name
            end
            next unless matching_rule

            # Get the attribute definition for this child
            attr_def = mapper_class.attributes[matching_rule.to]
            next unless attr_def

            # Build child's hoisted declarations
            # CRITICAL: Child elements with type namespace attributes need those
            # namespaces declared on themselves. Get type attribute namespaces from
            # child's own needs (stored in needs.children)
            child_hoisted = build_child_hoisted_declarations(attr_def, needs, options)

            # Create child DeclarationPlan with the child's namespace info
            # Children inherit parent's namespace_classes
            child_plan = DeclarationPlan.new(
              root_node: DeclarationPlan::ElementNode.new(
                qualified_name: xml_child.name,
                use_prefix: nil,
                hoisted_declarations: child_hoisted,
              ),
              global_prefix_registry: build_prefix_registry(needs),
              input_formats: {},
              namespace_classes: namespace_classes,
            )

            # Store by attribute name
            children_plans[attr_def.name] = child_plan
          end

          children_plans
        end

        # Build children_plans from mapper metadata (for nil/Class root_element)
        #
        # @param mapping [Xml::Mapping] XML mapping
        # @param needs [NamespaceNeeds] Namespace needs
        # @param options [Hash] Serialization options
        # @return [Hash<Symbol, DeclarationPlan>] Children plans by attribute name
        def build_children_plans_from_metadata(mapping, needs, options)
          children_plans = {}

          # Get mapper_class to find child attributes
          mapper_class = options[:mapper_class]
          return children_plans unless mapper_class.respond_to?(:attributes)

          # Build namespace_classes hash for child plans
          namespace_classes = {}
          needs.all_namespace_classes.each do |ns_class|
            namespace_classes[ns_class.uri] = ns_class
          end

          # Get parent's hoisted declarations for child inheritance
          parent_hoisted = build_parent_hoisted_for_children(mapping, needs,
                                                             options)

          # Iterate through mapper_class attributes
          mapper_class.attributes.each_value do |attr_def|
            # Check if attribute has a Serializable type
            attr_type = attr_def.type(@register)
            next unless attr_type
            next unless attr_type.is_a?(Class)
            next unless attr_type < Lutaml::Model::Serialize

            # Create child DeclarationPlan with parent's namespace_classes
            # Child inherits parent's hoisted declarations
            child_plan = DeclarationPlan.new(
              root_node: DeclarationPlan::ElementNode.new(
                qualified_name: "",
                use_prefix: nil,
                hoisted_declarations: parent_hoisted,
              ),
              global_prefix_registry: build_prefix_registry(needs),
              input_formats: {},
              namespace_classes: namespace_classes,
            )

            # Store by attribute name
            children_plans[attr_def.name] = child_plan
          end

          children_plans
        end

        # Build parent's hoisted declarations for child inheritance
        #
        # @param mapping [Xml::Mapping] XML mapping
        # @param needs [NamespaceNeeds] Namespace needs
        # @param options [Hash] Serialization options
        # @return [Hash<String|nil, String>] Hoisted declarations {prefix => uri}
        def build_parent_hoisted_for_children(mapping, needs, options)
          hoisted = {}

          # Get element's own namespace (from mapping's namespace_class)
          element_namespace = mapping&.namespace_class

          # Process namespace_scope configurations
          needs.namespace_scope_configs.each do |scope_config|
            ns_class = scope_config.namespace_class
            next if ns_class == element_namespace

            ns_usage = needs.namespace(ns_class.to_key)
            should_declare = scope_config.always_mode? ||
              (scope_config.auto_mode? && ns_usage&.used_in&.any?)

            if should_declare
              prefix = ns_class.prefix_default || "ns#{hoisted.keys.length}"
              hoisted[prefix] = ns_class.uri
            end
          end

          # Add element's own namespace (if not already added)
          if element_namespace && !hoisted.value?(element_namespace.uri)
            use_prefix_option = options[:use_prefix]

            case use_prefix_option
            when true
              prefix = element_namespace.prefix_default || "ns#{hoisted.keys.length}"
              hoisted[prefix] = element_namespace.uri
            when String
              hoisted[use_prefix_option] = element_namespace.uri
            when false
              hoisted[nil] = element_namespace.uri
            else
              # Default: prefer default format (cleaner)
              hoisted[nil] = element_namespace.uri
            end
          end

          # Add type namespaces
          # Type attribute namespaces
          needs.type_attribute_namespaces.each do |ns_class|
            ns_uri = ns_class.uri
            next if hoisted.value?(ns_uri)

            prefix = ns_class.prefix_default || "ns#{hoisted.keys.length}"
            hoisted[prefix] = ns_class.uri
          end

          # Type element namespaces
          needs.type_element_namespaces.each do |ns_class|
            ns_uri = ns_class.uri
            next if hoisted.value?(ns_uri)

            prefix = ns_class.prefix_default || "ns#{hoisted.keys.length}"
            hoisted[prefix] = ns_class.uri
          end

          # Add remaining namespaces
          needs.all_namespace_classes.each do |ns_class|
            ns_uri = ns_class.uri
            next if hoisted.value?(ns_uri)

            scope_config = needs.scope_config_for(ns_class)
            next if scope_config

            hoisted[nil] = ns_class.uri
          end

          hoisted
        end

        # Build hoisted declarations for a child element
        #
        # When a child element has attributes with type namespaces, those namespaces
        # must be declared on the child element itself (W3C compliance).
        #
        # @param attr_def [Attribute] The attribute definition for the child
        # @param needs [NamespaceNeeds] Namespace needs
        # @param options [Hash] Serialization options
        # @return [Hash<String|nil, String>] Hoisted declarations {prefix => uri}
        def build_child_hoisted_declarations(attr_def, needs, options)
          hoisted = {}

          # Get the child's own namespace needs
          child_needs = needs.child(attr_def.name)
          return hoisted unless child_needs

          # Add type attribute namespaces for the child element
          # CRITICAL: Type attribute namespaces MUST use prefix format (W3C rule)
          # NOTE: We only add type ATTRIBUTE namespaces, not type ELEMENT namespaces.
          # Type element namespaces are used by child elements and should be declared
          # on the parent element (or root, depending on namespace_scope).
          child_needs.type_attribute_namespaces.each do |ns_class|
            ns_uri = ns_class.uri
            next if hoisted.value?(ns_uri)

            prefix = ns_class.prefix_default || "ns#{hoisted.keys.length}"
            hoisted[prefix] = ns_class.uri
          end

          # Get child's element namespace if available
          child_type = attr_def.type(@register)
          if child_type && child_type.respond_to?(:<) && child_type < Lutaml::Model::Serialize
            child_mapping = child_type.mappings_for(:xml)
            if child_mapping && child_mapping.namespace_class
              element_namespace = child_mapping.namespace_class
              # Only add if not already present
              unless hoisted.value?(element_namespace.uri)
                # For child elements, prefer default format (cleaner)
                hoisted[nil] = element_namespace.uri
              end
            end
          end

          hoisted
        end

        # Build ElementNode for an XmlElement (recursive)
        #
        # @param xml_element [XmlDataModel::XmlElement] Element to plan
        # @param mapping [Xml::Mapping] XML mapping
        # @param needs [NamespaceNeeds] Namespace needs
        # @param options [Hash] Serialization options (may contain :input_formats)
        # @param parent_node [ElementNode, nil] Parent element node
        # @param is_root [Boolean] Whether this is the root element
        # @param parent_format [Symbol, nil] Parent's namespace format (:default or :prefix)
        # @param parent_namespace_class [Class, nil] Parent's namespace class
        # @param parent_hoisted [Hash] Namespaces hoisted on parent {prefix => uri}
        # @return [ElementNode] Element node with all decisions
        def build_element_node(xml_element, mapping, needs, options,
parent_node: nil, is_root: false, parent_format: nil, parent_namespace_class: nil, parent_hoisted: {})
          # Determine element's prefix (checks input_formats, parent context for preservation)
          element_prefix = determine_element_prefix(
            xml_element, mapping, needs, options,
            is_root: is_root,
            parent_format: parent_format,
            parent_namespace_class: parent_namespace_class,
            parent_hoisted: parent_hoisted
          )

          # Determine hoisted xmlns declarations at this element
          # CRITICAL: Pass element_prefix to avoid calling determine_element_prefix twice
          # which could return different results due to context differences
          hoisted = determine_hoisted_declarations(xml_element, mapping, needs,
                                                   options, is_root: is_root, parent_hoisted: parent_hoisted, element_prefix: element_prefix)

          # Determine if child needs xmlns="" (W3C compliance)
          # When parent has default namespace and child has no namespace,
          # child must explicitly opt out with xmlns="" ONLY for native type elements.
          # Child models should inherit parent's namespace by default.
          child_needs_xmlns_blank = xml_element.namespace_class.nil? &&
            parent_hoisted&.key?(nil) &&
            native_type_element?(xml_element)

          # Create ElementNode
          element_node = DeclarationPlan::ElementNode.new(
            qualified_name: build_qualified_element_name(xml_element,
                                                         element_prefix),
            use_prefix: element_prefix,
            hoisted_declarations: hoisted,
            needs_xmlns_blank: child_needs_xmlns_blank,
          )

          # Calculate this element's format for passing to children
          this_format = element_prefix.nil? ? :default : :prefix
          this_namespace = xml_element.namespace_class

          # Plan ALL attributes (PRESERVES ORDER)
          xml_element.attributes.each do |xml_attr|
            attr_node = plan_attribute(xml_attr, xml_element, mapping, options)
            element_node.add_attribute_node(attr_node)
          end

          # Get mapper_class from options to match children to mapping rules
          mapper_class = options[:mapper_class]
          attributes = mapper_class.respond_to?(:attributes) ? mapper_class.attributes : {}

          # Recursively plan ALL children (PRESERVES ORDER, mark as NOT root, pass parent context)
          xml_element.children.each do |xml_child|
            next unless xml_child.is_a?(Lutaml::Model::XmlDataModel::XmlElement)

            # Match child XmlElement to its mapping rule to get correct child mapping
            child_name = xml_child.name
            matching_rule = mapping.elements.find do |rule|
              rule.name.to_s == child_name
            end

            child_mapping = mapping # Default to parent mapping
            child_options = options

            if matching_rule && attributes.any?
              # Get child's mapper_class and mapping
              attr_def = attributes[matching_rule.to]
              if attr_def
                child_type = attr_def.type(@register)
                if child_type.respond_to?(:<) && child_type < Lutaml::Model::Serialize
                  child_mapping_obj = child_type.mappings_for(:xml)
                  if child_mapping_obj
                    child_mapping = child_mapping_obj
                    # CRITICAL: Pass parent's mapping so child can find its attribute name
                    # NOTE: do NOT propagate use_prefix to child elements
                    # use_prefix only applies to root element, not to children
                    # Children should use their own namespace's default presentation
                    use_prefix_value = options[:use_prefix]
                    if use_prefix_value == true
                      # Do NOT propagate use_prefix: true to children
                      # Children should use their own namespace's default presentation
                      child_options = options.except(:use_prefix).merge(mapper_class: child_type, parent_mapping: mapping)
                    elsif use_prefix_value.is_a?(String)
                      # Custom string prefix is specific to root's namespace - don't propagate
                      child_options = options.except(:use_prefix).merge(mapper_class: child_type, parent_mapping: mapping)
                    else
                      # use_prefix: false or nil - don't propagate
                      child_options = options.except(:use_prefix).merge(mapper_class: child_type, parent_mapping: mapping)
                    end
                  end
                end
              end
            end

            child_node = build_element_node(
              xml_child, child_mapping, needs, child_options,
              parent_node: element_node,
              is_root: false,
              parent_format: this_format,
              parent_namespace_class: this_namespace,
              parent_hoisted: hoisted
            )
            element_node.add_element_node(child_node)
          end

          element_node
        end

        # Plan attribute prefix using W3C attributeFormDefault semantics
        #
        # W3C Rules (MECE):
        # 1. Same namespace + unqualified → NO prefix
        # 2. Different namespace OR qualified → YES prefix
        # 3. Only attribute has namespace → YES prefix
        # 4. No namespace but qualified → inherit element prefix
        # 5. No namespace, unqualified → NO prefix (W3C default)
        #
        # @param xml_attr [XmlDataModel::XmlAttribute] Attribute to plan
        # @param xml_element [XmlDataModel::XmlElement] Parent element
        # @param mapping [Xml::Mapping] XML mapping
        # @param options [Hash] Serialization options
        # @return [AttributeNode] Attribute decision node
        def plan_attribute(xml_attr, xml_element, _mapping, _options)
          attr_ns_class = xml_attr.namespace_class
          element_ns_class = xml_element.namespace_class

          # Get W3C attributeFormDefault setting
          attribute_form_default = element_ns_class&.attribute_form_default || :unqualified

          # Compare by URI since namespace classes can be different instances
          # with the same URI (e.g., dynamically created in tests with Class.new)
          same_namespace = attr_ns_class && element_ns_class &&
                          attr_ns_class.uri == element_ns_class.uri

          # W3C Attribute Prefix Decision (MECE)
          use_prefix = if same_namespace && attribute_form_default == :unqualified
                         # Priority 1: Same namespace + unqualified → NO prefix
                         nil
                       elsif attr_ns_class && element_ns_class
                         # Priority 2: Different namespace OR qualified → YES prefix
                         attr_ns_class.prefix_default
                       elsif attr_ns_class
                         # Priority 3: Only attribute has namespace → YES prefix
                         attr_ns_class.prefix_default
                       elsif attribute_form_default == :qualified
                         # Priority 4: No namespace but qualified → inherit element prefix
                         element_ns_class&.prefix_default
                       else
                         # Priority 5: No namespace, unqualified → NO prefix (W3C default)
                         nil
                       end

          DeclarationPlan::AttributeNode.new(
            local_name: xml_attr.name,
            use_prefix: use_prefix,
            namespace_uri: attr_ns_class&.uri,
          )
        end

        # Determine element's prefix using the OOP decision system
        #
        # Uses ElementPrefixResolver instead of procedural if-else chain.
        #
        # @param xml_element [XmlDataModel::XmlElement] Element
        # @param mapping [Xml::Mapping] XML mapping
        # @param needs [NamespaceNeeds] Namespace needs
        # @param options [Hash] Serialization options
        # @param is_root [Boolean] Whether this is the root element
        # @param parent_format [Symbol, nil] Parent's format (:prefix or :default)
        # @param parent_namespace_class [Class, nil] Parent's namespace class
        # @param parent_hoisted [Hash] Namespaces hoisted on parent {prefix => uri}
        # @return [String, nil] The prefix to use, or nil for default format
        def find_type_namespace_for_element(xml_element, mapping, needs,
options)
          # Get mapper_class from options
          mapper_class = options[:mapper_class]
          return nil unless mapper_class

          # Get attributes from mapper_class
          attributes = mapper_class.respond_to?(:attributes) ? mapper_class.attributes : {}
          return nil unless attributes.any?

          # Find matching element rule
          element_name = xml_element.name.to_s
          matching_rule = mapping.elements.find do |rule|
            rule.name.to_s == element_name
          end
          return nil unless matching_rule

          # Get attribute definition
          attr_def = attributes[matching_rule.to]
          return nil unless attr_def

          # Look up type namespace from needs.type_namespaces
          needs.type_namespaces[attr_def&.name]
        end

        def determine_element_prefix(xml_element, mapping, needs, options,
                                     is_root: false,
                                     parent_format: nil,
                                     parent_namespace_class: nil,
                                     parent_hoisted: {})
          # CRITICAL: Check for Type namespace FIRST
          # Type namespaces are declared on Type::Value subclasses and used as
          # prefixes on child elements. They take precedence over element namespace.
          type_ns_class = find_type_namespace_for_element(xml_element, mapping,
                                                          needs, options)
          if type_ns_class
            # If parent uses default format AND Type namespace matches parent's namespace,
            # inherit parent's namespace (return nil for prefix)
            if parent_format == :default && parent_namespace_class&.uri == type_ns_class.uri
              return nil
            end

            # CRITICAL: Check if parent hoisted this type namespace with a custom prefix
            # When user specifies prefix: "custom", the parent hoists the namespace
            # with that custom prefix, and child elements must use the same prefix
            parent_prefix = parent_hoisted.find do |_prefix, uri|
              uri == type_ns_class.uri
            end&.first
            if parent_prefix
              return parent_prefix
            end

            # CRITICAL: Check if user specified an explicit custom prefix option
            # This handles the case where parent hasn't hoisted yet AND the type namespace
            # matches the parent's namespace (i.e., they share the same namespace)
            use_prefix_option = options[:use_prefix]
            if use_prefix_option && parent_namespace_class && parent_namespace_class.uri == type_ns_class.uri
              # Parent has the same namespace as the type namespace
              # Use the prefix option to maintain consistency
              case use_prefix_option
              when String
                return use_prefix_option
              when true
                return parent_namespace_class.prefix_default
              when false
                return nil
              end
            end

            # Default: use the Type namespace's prefix_default
            return type_ns_class.prefix_default
          end

          # If no Type namespace, check element's own namespace
          return nil unless xml_element.namespace_class

          # Use the OOP decision resolver
          @prefix_resolver ||= Decisions::ElementPrefixResolver.new
          decision = @prefix_resolver.resolve_with_decision(
            xml_element, mapping, needs, options,
            is_root: is_root,
            parent_format: parent_format,
            parent_namespace_class: parent_namespace_class,
            parent_hoisted: parent_hoisted
          )

          decision.prefix
        end

        # Build qualified element name with prefix
        #
        # @param xml_element [XmlDataModel::XmlElement] Element
        # @param prefix [String, nil] Prefix (nil = no prefix)
        # @return [String] Qualified name: "prefix:name" or "name"
        def build_qualified_element_name(xml_element, prefix)
          if prefix
            "#{prefix}:#{xml_element.name}"
          else
            xml_element.name
          end
        end

        # Determine which xmlns declarations to hoist at this element
        #
        # Checks input_formats to preserve input format during round-trip.
        #
        # @param xml_element [XmlDataModel::XmlElement] Element
        # @param mapping [Xml::Mapping] XML mapping
        # @param needs [NamespaceNeeds] Namespace needs
        # @param options [Hash] Serialization options (may contain :input_formats)
        # @param is_root [Boolean] Whether this is the root element
        # @param parent_hoisted [Hash] Namespaces hoisted on parent {prefix => uri}
        # @return [Hash<String|nil, String>] xmlns attributes: {prefix_or_nil => uri}
        def determine_hoisted_declarations(xml_element, mapping, needs,
options, is_root: false, parent_hoisted: {}, element_prefix: nil)
          hoisted = {}

          # CRITICAL: Get the current element's namespace_scope_configs
          # For child elements, use their own namespace_scope, not the parent's
          current_scope_configs = get_element_namespace_scope_configs(xml_element, mapping, needs, options)

          # Check if element's namespace is hoisted to root via namespace_scope
          element_ns_hoisted_to_root = false
          if xml_element.namespace_class
            scope_config = find_scope_config_for(xml_element.namespace_class, current_scope_configs)
            if scope_config
              ns_usage = needs.namespaces[xml_element.namespace_class.to_key]
              element_ns_hoisted_to_root = scope_config.always_mode? ||
                (scope_config.auto_mode? && ns_usage&.used_in&.any?)
            end
          end

          # Check if element's namespace was already hoisted on parent (locally)
          false
          if xml_element.namespace_class
            ns_uri = xml_element.namespace_class.uri
            parent_hoisted.value?(ns_uri)
          end

          # FIRST: Add element's OWN namespace if it has one
          # This ensures the namespace is declared with the correct format (prefix or default)
          # even when it's already hoisted by parent, to maintain consistency.
          if xml_element.namespace_class
            ns_class = xml_element.namespace_class
            ns_uri = ns_class.uri

            # Check if namespace is hoisted on parent
            ns_hoisted_by_parent = parent_hoisted.value?(ns_uri)

            # Check if namespace is hoisted to root via namespace_scope (for non-root elements)
            ns_hoisted_to_root = element_ns_hoisted_to_root && !is_root

            # Determine the prefix to use for this namespace
            if !ns_hoisted_by_parent && !ns_hoisted_to_root
              # Namespace is NOT already hoisted - need to determine prefix
              element_prefix = determine_element_prefix(xml_element, mapping,
                                                        needs, options, is_root: is_root, parent_hoisted: parent_hoisted)
              hoisted[element_prefix] = ns_uri
            elsif element_prefix
              # Namespace is already hoisted by parent
              # Check if parent has the SAME prefix declaration
              parent_has_same_prefix = parent_hoisted.key?(element_prefix) && parent_hoisted[element_prefix] == ns_uri
              if parent_has_same_prefix
                # Parent already declared this namespace with the same prefix - don't re-declare
                # Just keep track that we're using the parent's prefix (no need to add to hoisted)
              else
                # Parent has different prefix or no prefix - add our declaration
                hoisted[element_prefix] = ns_uri
              end
            else
              # Namespace is hoisted by parent, but we don't have a prefix
              # Check if parent used default format (nil prefix) for this namespace
              parent_prefix = parent_hoisted.find do |_prefix, uri|
                uri == ns_uri
              end&.first
              if parent_prefix
                # Parent used prefix format - use same prefix
                hoisted[parent_prefix] = ns_uri
              else
                # Parent used default format - use default format
                hoisted[nil] = ns_uri
              end
            end

            # CRITICAL FIX: If root element uses default format (nil prefix) and child elements
            # need prefix format for the same namespace (due to form: :qualified), also declare
            # the namespace with prefix format on the root element.
            # This allows child elements to use the prefix without declaring it locally.
            # IMPORTANT: This only applies to the element's OWN namespace, not type namespaces.
            # Type namespaces should be declared locally on the element that uses the type.
            if is_root && hoisted.key?(nil) && hoisted[nil] == ns_uri
              # Check if any child elements have form: :qualified for this namespace
              # by checking the children's form attribute in the XmlElement tree
              if xml_element.respond_to?(:children)
                child_needs_prefix = xml_element.children.any? do |child|
                  next unless child.is_a?(Lutaml::Model::XmlDataModel::XmlElement)
                  # Check if child has form: :qualified and same namespace
                  child.form == :qualified && child.namespace_class&.uri == ns_uri
                end
                if child_needs_prefix
                  prefix = ns_class.prefix_default
                  hoisted[prefix] = ns_uri
                end
              end
            end
          end

          # SECOND: Add namespace_scope namespaces (ONLY at root!)
          if is_root
            current_scope_configs.each do |scope_config|
              ns_class = scope_config.namespace_class

              # Skip if already added (element's own namespace)
              next if ns_class == xml_element.namespace_class

              # CRITICAL: Skip if namespace URI is already in hoisted hash
              # An element can declare the same URI with both default and prefix formats
              next if hoisted.value?(ns_class.uri) || hoisted.key?(ns_class.prefix_default)

              # Check :always mode or :auto mode with usage
              ns_usage = needs.namespace(ns_class.to_key)
              should_declare_here = scope_config.always_mode? ||
                (scope_config.auto_mode? && ns_usage&.used_in&.any?)

              if should_declare_here
                prefix = ns_class.prefix_default
                hoisted[prefix] = ns_class.uri
              end
            end
          end

          # THIRD: Add type namespaces
          # Type namespaces are declared on PARENT elements and used by child elements.
          # W3C rule: Namespaces in attributes MUST use prefix format.
          # Type namespaces for elements MUST also be declared at root with prefix.
          # Example: ContactInfo declares xmlns:name for personName's name:prefix attribute.
          # Example: Document declares xmlns:dc for title's dc:title element.
          #
          # CRITICAL: Type namespaces respect namespace_scope directive.
          # When namespace_scope is configured, hoist type namespaces to root.
          # When namespace_scope is NOT configured, type namespaces are declared
          # locally on the elements that use them.
          if is_root
            # Check if namespace_scope is configured
            has_namespace_scope = !current_scope_configs.empty?

            # Only hoist type namespaces to root when namespace_scope is configured
            if has_namespace_scope
              # Type attribute namespaces
              needs.type_attribute_namespaces.each do |ns_class|
                ns_uri = ns_class.uri
                next if hoisted.value?(ns_uri) # Skip if already declared
                next if ns_class == xml_element.namespace_class # Skip element's own namespace

                # If namespace_scope is configured, only hoist if in scope
                scope_config = find_scope_config_for(ns_class, current_scope_configs)
                next unless scope_config

                # Type attribute namespaces MUST use prefix format (W3C rule)
                prefix = ns_class.prefix_default || "ns#{hoisted.keys.length}"
                hoisted[prefix] = ns_uri
              end

              # Type element namespaces
              needs.type_element_namespaces.each do |ns_class|
                ns_uri = ns_class.uri
                next if hoisted.value?(ns_uri) # Skip if already declared
                next if ns_class == xml_element.namespace_class # Skip element's own namespace

                # CRITICAL: Type namespaces are different from child element namespaces.
                # Type namespaces are declared on Type::Value subclasses (via xml_namespace
                # directive) and MUST ALWAYS be hoisted to root with prefix format (W3C
                # constraint: only one default namespace per element).
                #
                # The restriction below applies ONLY to child element namespaces (from nested
                # models), NOT to Type namespaces. Type namespaces are about TYPE identity,
                # not about element structure.
                #
                # Examples of child element namespaces (should NOT be hoisted if different):
                # - Root has XMI namespace, child model has XMI_NEW namespace → child declares
                # - Root has NO namespace, child model has XMI namespace → child declares
                #
                # Examples of Type namespaces (should ALWAYS be hoisted):
                # - Root has any namespace, attribute type has XMI namespace → hoist XMI
                # - Root has NO namespace, attribute type has XMI namespace → hoist XMI

                # If namespace_scope is configured, only hoist if in scope
                scope_config = find_scope_config_for(ns_class, current_scope_configs)
                next unless scope_config

                # Type element namespaces MUST use prefix format
                prefix = ns_class.prefix_default || "ns#{hoisted.keys.length}"
                hoisted[prefix] = ns_uri
              end
            else
              # Root element without namespace_scope: hoist type namespaces
              # Type namespaces MUST use prefix format (W3C rule)
              #
              # CRITICAL: Don't hoist type namespaces that are also child element
              # namespaces. When a type namespace is also a child's element namespace, it
              # should be declared on that child element (not hoisted to root).

              # Type element namespaces (for Type::Value classes used by root's attributes)
              needs.type_element_namespaces.each do |ns_class|
                ns_uri = ns_class.uri
                next if hoisted.value?(ns_uri) # Skip if already declared
                next if ns_class == xml_element.namespace_class # Skip element's own namespace

                # Check if this namespace is used by any child element as its element namespace
                # If so, don't hoist - let the child declare it locally
                # UNLESS the parent also uses this namespace for its attributes
                child_uses_namespace = needs.children&.any? do |_attr_name, child_needs|
                  child_needs.namespaces.any? do |_key, ns_usage|
                    ns_usage.used_in_elements? && ns_usage.namespace_class.uri == ns_uri
                  end
                end

                # Only skip hoisting if child uses namespace AND parent doesn't use it for attributes
                # Check if parent element instance has attributes with this namespace
                parent_has_attr_with_ns = if xml_element && xml_element.respond_to?(:attributes)
                  xml_element.attributes.any? do |xml_attr|
                    next false unless xml_attr.namespace_class
                    xml_attr.namespace_class.uri == ns_uri
                  end
                else
                  # For nil/Class root_element, check if mapping has attributes with this namespace
                  # This handles the case where parent doesn't have the attribute set
                  # Only hoist if parent's MAPPING declares attributes with this namespace
                  mapping.attributes.any? do |attr_rule|
                    next false unless attr_rule.attribute?

                    # Get the mapper_class to find attribute definition
                    mapper_class = options[:mapper_class] || mapping.owner
                    next false unless mapper_class
                    next false unless mapper_class.respond_to?(:attributes)

                    attr_def = mapper_class.attributes[attr_rule.to]
                    next false unless attr_def

                    # Check if this attribute's type has the namespace
                    type_ns_class = attr_def.type_namespace_class(@register)
                    type_ns_class&.uri == ns_uri
                  end
                end
                next if child_uses_namespace && !parent_has_attr_with_ns

                prefix = ns_class.prefix_default || "ns#{hoisted.keys.length}"
                hoisted[prefix] = ns_uri
              end

              # Type attribute namespaces (for Type::Value classes used in child element attributes)
              # CRITICAL: Don't hoist if namespace is also child element's namespace
              needs.type_attribute_namespaces.each do |ns_class|
                ns_uri = ns_class.uri
                next if hoisted.value?(ns_uri) # Skip if already declared
                next if ns_class == xml_element.namespace_class # Skip element's own namespace

                # Check if this namespace is used by any child element as its element namespace
                # If so, don't hoist - let the child declare it locally
                child_uses_namespace = needs.children&.any? do |_attr_name, child_needs|
                  child_needs.namespaces.any? do |_key, ns_usage|
                    ns_usage.used_in_elements? && ns_usage.namespace_class.uri == ns_uri
                  end
                end

                # Only skip hoisting if child uses namespace AND parent doesn't use it for attributes
                parent_has_attr_with_ns = if xml_element && xml_element.respond_to?(:attributes)
                  xml_element.attributes.any? do |xml_attr|
                    next false unless xml_attr.namespace_class
                    xml_attr.namespace_class.uri == ns_uri
                  end
                else
                  # For nil/Class root_element, check if mapping has attributes with this namespace
                  mapping.attributes.any? do |attr_rule|
                    next false unless attr_rule.attribute?

                    mapper_class = options[:mapper_class] || mapping.owner
                    next false unless mapper_class
                    next false unless mapper_class.respond_to?(:attributes)

                    attr_def = mapper_class.attributes[attr_rule.to]
                    next false unless attr_def

                    type_ns_class = attr_def.type_namespace_class(@register)
                    type_ns_class&.uri == ns_uri
                  end
                end

                next if child_uses_namespace && !parent_has_attr_with_ns

                prefix = ns_class.prefix_default || "ns#{hoisted.keys.length}"
                hoisted[prefix] = ns_uri
              end
            end
          else
            # For non-root (child) elements, add their own type namespaces
            # CRITICAL: Child elements with type namespace attributes need those
            # namespaces declared on themselves (W3C compliance)
            #
            # Get the child's own namespace needs by matching the current element
            # to its corresponding attribute name in the parent's mapping
            child_attr_name = find_child_attribute_name(xml_element, mapping, options)
            if child_attr_name
              child_needs = needs.child(child_attr_name)
              if child_needs
                # Add child's type element namespaces (for Type::Value attributes)
                # These need to be hoisted to the child element
                child_needs.type_element_namespaces.each do |ns_class|
                  ns_uri = ns_class.uri
                  next if hoisted.value?(ns_uri) # Skip if already declared
                  next if parent_hoisted.value?(ns_uri) # Skip if parent already declared
                  next if ns_class == xml_element.namespace_class # Skip element's own namespace

                  # Type namespaces MUST use prefix format (W3C rule)
                  prefix = ns_class.prefix_default || "ns#{hoisted.keys.length}"
                  hoisted[prefix] = ns_uri
                end

                # Add child's type attribute namespaces
                # CRITICAL: Skip if namespace is child's own element namespace
                # The element's namespace declaration already covers it
                child_needs.type_attribute_namespaces.each do |ns_class|
                  ns_uri = ns_class.uri
                  next if hoisted.value?(ns_uri) # Skip if already declared
                  next if parent_hoisted.value?(ns_uri) # Skip if parent already declared
                  next if ns_class == xml_element.namespace_class # Skip element's own namespace

                  # Type attribute namespaces MUST use prefix format (W3C rule)
                  prefix = ns_class.prefix_default || "ns#{hoisted.keys.length}"
                  hoisted[prefix] = ns_uri
                end
              end
            end
          end

          # FOURTH: Add namespaces NOT in namespace_scope (LOCAL hoisting)
          # W3C minimal-subtree principle: declare namespace at first element using it
          if !is_root
            needs.namespaces.each_value do |ns_usage|
              ns_class = ns_usage.namespace_class

              # Skip if already added (element's own namespace)
              next if ns_class == xml_element.namespace_class

              # Skip if already hoisted on parent (don't redeclare!)
              next if parent_hoisted.value?(ns_class.uri)

              # CRITICAL: Skip if this namespace is ONLY used by child elements (not by
              # the current element). Child elements should declare their own namespace
              # locally using default format. But if the current element uses this namespace
              # for its attributes, it should be hoisted.
              # Check: if NOT used in attributes AND used in elements → skip hoisting
              # NOTE: Also check type_attribute_namespaces (attribute type namespaces)
              used_in_attributes = ns_usage.used_in_attributes? || needs.type_attribute_namespaces.include?(ns_class)
              next if !used_in_attributes && ns_usage.used_in_elements?

              scope_config = find_scope_config_for(ns_class, current_scope_configs)

              # Only hoist if NOT in namespace_scope (local hoisting)
              # Check if any child/grandchild uses this namespace
              if !scope_config && element_needs_namespace?(xml_element,
                                                           ns_class)
                prefix = ns_class.prefix_default
                hoisted[prefix] = ns_class.uri
              end
            end
          end

          hoisted
        end

        # Find the attribute name for a child XmlElement
        #
        # When building child element nodes, we need to match the XmlElement to its
        # corresponding attribute name in the parent's mapping to access the child's
        # own namespace needs.
        #
        # @param xml_element [XmlDataModel::XmlElement] The child element
        # @param mapping [Xml::Mapping] The current element's mapping (parent's for child elements)
        # @param options [Hash] Serialization options (may contain :parent_mapping)
        # @return [Symbol, nil] The attribute name, or nil if not found
        def find_child_attribute_name(xml_element, mapping, options = {})
          # Use parent's mapping if available (for child elements)
          search_mapping = options[:parent_mapping] || mapping

          element_name = xml_element.name.to_s
          matching_rule = search_mapping.elements.find do |rule|
            rule.name.to_s == element_name
          end

          matching_rule&.to
        end

        # Get the current element's namespace_scope_configs
        #
        # For child elements, use their own namespace_scope, not the parent's.
        # This ensures that namespace_scope directives are scoped to the model that defines them.
        #
        # @param xml_element [XmlDataModel::XmlElement] The element
        # @param mapping [Xml::Mapping] The element's mapping
        # @param needs [NamespaceNeeds] Namespace needs
        # @param options [Hash] Serialization options
        # @return [Array<NamespaceScopeConfig>] The element's namespace_scope_configs
        def get_element_namespace_scope_configs(xml_element, mapping, needs, options)
          # Use the parent's namespace_scope_configs
          needs.namespace_scope_configs
        end

        # Find a scope config for a namespace class
        #
        # @param ns_class [Class] The namespace class
        # @param scope_configs [Array<NamespaceScopeConfig>] The scope configs to search
        # @return [NamespaceScopeConfig, nil] The matching scope config, or nil
        def find_scope_config_for(ns_class, scope_configs)
          scope_configs.find { |config| config.namespace_class == ns_class }
        end

        # Build global prefix registry from needs
        #
        # @param needs [NamespaceNeeds] Namespace needs
        # @return [Hash<String, String>] URI => prefix mapping
        def build_prefix_registry(needs)
          registry = {}
          needs.namespaces.each_value do |ns_usage|
            ns_class = ns_usage.namespace_class
            if ns_class.prefix_default
              registry[ns_class.uri] =
                ns_class.prefix_default
            end
          end
          registry
        end

        # Check if element or its descendants use a namespace
        #
        # @param xml_element [XmlDataModel::XmlElement] Element to check
        # @param ns_class [Class] Namespace class to search for
        # @return [Boolean] true if namespace is used in subtree
        def element_needs_namespace?(xml_element, ns_class)
          # Check direct children
          xml_element.children.each do |child|
            next unless child.is_a?(Lutaml::Model::XmlDataModel::XmlElement)

            # Does child use this namespace?
            return true if child.namespace_class == ns_class

            # Does child have attributes using this namespace?
            child.attributes.each do |attr|
              return true if attr.namespace_class == ns_class
            end

            # Recurse to grandchildren
            return true if element_needs_namespace?(child, ns_class)
          end

          false
        end

        # Check if element is a native type element (leaf with text content)
        #
        # Native type elements (like :string, :integer) are simple values
        # that need xmlns="" when parent uses default namespace format.
        # Child models are complex elements with their own structure.
        #
        # @param xml_element [XmlDataModel::XmlElement] Element to check
        # @return [Boolean] true if element is a native type element
        def native_type_element?(xml_element)
          # Native type elements have:
          # - text_content (not nil)
          # - No element children (all children are Strings, not XmlElement)
          return false unless xml_element.text_content

          xml_element.children.all?(String)
        end
      end
    end
  end
end
