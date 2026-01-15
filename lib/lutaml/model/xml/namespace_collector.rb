# frozen_string_literal: true

require "set"
require_relative "../utils"
require_relative "namespace_needs"
require_relative "namespace_usage"
require_relative "type_namespace/reference"
require_relative "namespace_scope_config"

module Lutaml
  module Model
    module Xml
      # Phase 1: Bottom-Up Collection
      #
      # Walks the model tree from leaves to root, collecting namespace needs.
      # This provides full tree knowledge before any declaration decisions are made.
      #
      # CRITICAL ARCHITECTURAL PRINCIPLE:
      # XmlNamespace CLASS is the atomic unit of namespace configuration.
      # Never track URI and prefix separately - they are inseparable.
      #
      # REFACTORED (Session 176):
      # Returns NamespaceNeeds object instead of schema-less hash
      # Uses NamespaceUsage, TypeNamespace::Reference, NamespaceScopeConfig objects
      #
      # @example
      #   collector = NamespaceCollector.new(register)
      #   needs = collector.collect(model_instance, mapping)
      #
      class NamespaceCollector
        # Initialize collector with register for type resolution
        #
        # @param register [Symbol] the register ID for type resolution
        def initialize(register = nil)
          @register = register || Lutaml::Model::Config.default_register

          # VISITED TYPE TRACKING
          # Thread-local call stack for circular reference detection
          Thread.current[:namespace_collector_call_stack] ||= []
        end

        # Collect namespace needs for an element and its descendants
        #
        # @param element [Object] the model instance (can be nil for type analysis)
        # @param mapping [Xml::Mapping] the XML mapping for this element
        # @param options [Hash] additional options including mapper_class for recursive calls
        # @return [NamespaceNeeds] namespace needs structure
        def collect(element, mapping, visited: nil, **options)
          # If this is a top-level call (no visited yet), ensure cleanup
          if visited.nil?
            Thread.current[:namespace_collector_call_stack] = []
            begin
              collect_internal(element, mapping, visited: nil, **options)
            ensure
              Thread.current[:namespace_collector_call_stack] = nil
            end
          else
            # Nested call - don't clean up yet
            collect_internal(element, mapping, visited: visited, **options)
          end
        end

        # Collect namespace needs for a collection of instances
        #
        # @param collection [Collection] the collection instance
        # @param mapping [Xml::Mapping] the XML mapping for the collection
        # @return [NamespaceNeeds] aggregated namespace needs
        def collect_collection(collection, mapping)
          needs = collect(nil, mapping)

          # If collection has instances, collect needs from instance type
          if collection.respond_to?(:instances) &&
              mapping.respond_to?(:find_element)
            instance_rule = mapping.find_element(:instances) ||
              mapping.elements.first
            if instance_rule
              attr_def = collection.class.attributes[instance_rule.to]
              if attr_def
                instance_type = attr_def.type(@register)
                if instance_type.respond_to?(:<) &&
                    instance_type < Lutaml::Model::Serialize
                  instance_mapping = instance_type.mappings_for(:xml)
                  if instance_mapping
                    instance_needs = collect(nil, instance_mapping)
                    needs.merge(instance_needs)
                  end
                end
              end
            end
          end

          needs
        end

        # Check if namespace needs require prefix for root element
        #
        # This implements the W3C rule: if any XML attributes are in the
        # same namespace as the root element, the root must use a prefix.
        #
        # @param needs [NamespaceNeeds] the collected namespace needs
        # @param mapping [Xml::Mapping] the root element mapping
        # @return [Boolean] true if prefix is required
        def needs_prefix?(needs, mapping)
          return false unless mapping.namespace_class

          # Look up by string key
          key = mapping.namespace_class.to_key
          usage = needs.namespace(key)
          usage && usage.used_in_attributes?
        end

        # Get all unique namespaces that need declaration
        #
        # @param needs [NamespaceNeeds] the collected namespace needs
        # @return [Set<Class>] set of XmlNamespace classes
        def all_namespaces(needs)
          needs.all_namespace_classes
        end

        # Check if a namespace is used in descendants
        #
        # @param needs [NamespaceNeeds] the collected namespace needs
        # @param namespace_class [Class] the XmlNamespace class to check
        # @return [Boolean] true if namespace is used in tree
        def namespace_used?(needs, namespace_class)
          validate_namespace_class(namespace_class)

          # Look up by string key
          key = namespace_class.to_key
          return true if needs.namespace(key)

          needs.children.each_value do |child_needs|
            return true if namespace_used?(child_needs, namespace_class)
          end

          false
        end

        private

        attr_reader :register

        # Validate that an object is an XmlNamespace class
        #
        # @param ns_class [Object] the object to validate
        # @raise [ArgumentError] if not an XmlNamespace class
        def validate_namespace_class(ns_class)
          return if ns_class.nil?
          return if ns_class == :blank  # Allow :blank symbol for explicit blank namespace

          unless ns_class.is_a?(Class) && ns_class < Lutaml::Model::Xml::Namespace
            raise ArgumentError,
                  "Namespace must be XmlNamespace class, got #{ns_class.class}. " \
                  "Same URI + different prefix = different XmlNamespace class."
          end
        end

        # Track namespace usage in needs structure
        #
        # @param needs [NamespaceNeeds] the needs structure
        # @param ns_class [Class] the XmlNamespace class
        # @param usage [Symbol] :elements or :attributes
        def track_namespace(needs, ns_class, usage)
          # Skip tracking for :blank namespace (explicit no namespace)
          return if ns_class == :blank

          key = ns_class.to_key
          existing = needs.namespace(key)

          if existing
            existing.mark_used_in(usage)
          else
            usage_obj = NamespaceUsage.new(ns_class)
            usage_obj.mark_used_in(usage)
            needs.add_namespace(key, usage_obj)
          end
        end

        # Merge child namespace needs into parent needs
        #
        # CRITICAL FIX (Session 205): ALWAYS merge used_in Sets
        # For XmlElement trees, child's used_in represents ACTUAL usage that must bubble up.
        # The previous "element-local only" approach was incorrect - it broke grandchildren collection.
        #
        # @param parent_needs [NamespaceNeeds] the parent needs structure
        # @param child_needs [NamespaceNeeds] the child needs structure
        def merge_namespace_needs(parent_needs, child_needs)
          # Merge via NamespaceNeeds.merge method
          # But we need special handling for children_use and children_need_prefix
          child_needs.namespaces.each do |key, child_usage|
            parent_usage = parent_needs.namespace(key)

            if parent_usage
              # ✅ FIX: MERGE used_in Sets (this was the bug!)
              # Grandchildren's actual usage MUST bubble up to parent
              parent_usage.used_in.merge(child_usage.used_in)

              # Track that children use this namespace
              parent_usage.mark_child_use(child_usage.namespace_class)

              # CASCADING PREFIX: If child uses in attributes OR needs prefix for its children
              if child_usage.used_in_attributes? || child_usage.children_need_prefix
                parent_usage.children_need_prefix = true
              end
            else
              # Create new usage for parent
              new_usage = NamespaceUsage.new(child_usage.namespace_class)

              # ✅ FIX: COPY used_in from child (this was the bug!)
              # Grandchildren's actual usage becomes parent's used_in
              new_usage.used_in.merge(child_usage.used_in)

              # Mark that children use it
              new_usage.mark_child_use(child_usage.namespace_class)

              # Cascade prefix requirement
              if child_usage.used_in_attributes? || child_usage.children_need_prefix
                new_usage.children_need_prefix = true
              end

              parent_needs.add_namespace(key, new_usage)
            end
          end

          # CRITICAL: Merge Type refs (Type namespaces MUST bubble up!)
          # Type namespaces are declared on PARENT elements and used by child elements.
          # Example: Contact.title uses DcTitleType, so dc namespace must be declared
          # on <contact> element, then <dc:title> uses the prefix.
          child_needs.type_refs.each do |ref|
            parent_needs.add_type_ref(ref)
          end

          # Merge namespace scope configs
          child_needs.namespace_scope_configs.each do |config|
            parent_needs.add_namespace_scope_config(config)
          end
        end

        # Internal collection method
        #
        # @param element [Object] the model instance (can be nil for type analysis)
        # @param mapping [Xml::Mapping] the XML mapping for this element
        # @param options [Hash] additional options including mapper_class for recursive calls
        # @return [NamespaceNeeds] namespace needs structure
        def collect_internal(element, mapping, visited: nil, **options)
          needs = NamespaceNeeds.new

          # Check if element is XmlDataModel::XmlElement
          if element.is_a?(Lutaml::Model::XmlDataModel::XmlElement)
            return collect_from_xml_element(element, mapping, needs, **options)
          end

          # Get mapper_class from element or from options (for recursive calls)
          mapper_class = element&.class || options&.dig(:mapper_class)

          # Prevent infinite recursion using CALL STACK
          if mapper_class
            call_stack = Thread.current[:namespace_collector_call_stack]
            if call_stack.include?(mapper_class)
              # Type is currently on call stack - circular reference detected
              return NamespaceNeeds.new
            end
            # Add to call stack - will be removed in ensure block
            call_stack.push(mapper_class)
          end

          begin
            attributes = mapper_class.respond_to?(:attributes) ? mapper_class.attributes : {}

            # ==================================================================
            # PHASE 1: OWN NAMESPACE COLLECTION (for non-type-only models)
            # ==================================================================
            unless mapping.no_element?
              # Collect own element namespace
              if mapping.namespace_class
                validate_namespace_class(mapping.namespace_class)
                track_namespace(needs, mapping.namespace_class, :elements)
              end

              # ==================================================================
              # PHASE 2: XML ATTRIBUTE NAMESPACE COLLECTION
              # ==================================================================
              mapping.attributes.each do |attr_rule|
                next unless attr_rule.attribute?
                next if attr_rule.to.nil?
                next unless attributes&.any?

                attr_def = attributes[attr_rule.to]

                # INSTANCE-AWARE COLLECTION
                if element
                  value = element.send(attr_rule.to) if element.respond_to?(attr_rule.to)
                  next if value.nil? || Utils.uninitialized?(value)
                end

                # Resolve attribute namespace
                ns_class = nil
                if attr_rule.namespace_set?
                  # Explicit namespace on attribute rule
                  ns_class = attr_rule.namespace_class || mapping.namespace_class
                elsif attr_rule.namespace_class
                  # Implicit namespace from attribute class
                  ns_class = attr_rule.namespace_class
                elsif attr_def
                  # TYPE NAMESPACE INTEGRATION
                  # Store TypeNamespace::Reference for lazy resolution in DeclarationPlanner
                  if attr_def
                    ref = TypeNamespace::Reference.new(attr_def, attr_rule, :attribute)
                    needs.add_type_ref(ref)
                  end
                end

                if ns_class
                  validate_namespace_class(ns_class)
                  track_namespace(needs, ns_class, :attributes)
                end
              end

              # ==================================================================
              # PHASE 3: NAMESPACE_SCOPE CONFIGURATION
              # ==================================================================
              if mapping.respond_to?(:namespace_scope_config) && mapping.namespace_scope_config&.any?
                mapping.namespace_scope_config.each do |cfg|
                  config = NamespaceScopeConfig.new(cfg[:namespace], cfg[:declare] || :auto)
                  needs.add_namespace_scope_config(config)
                end
              end
            end

            # ==================================================================
            # PHASE 4: ELEMENT NAMESPACE COLLECTION & RECURSION
            # ==================================================================
            mapping.elements.each do |elem_rule|
              # Collect explicit element namespace if set
              if elem_rule.namespace_set? && elem_rule.namespace_class
                validate_namespace_class(elem_rule.namespace_class)
                track_namespace(needs, elem_rule.namespace_class, :elements)
              end

              next unless attributes&.any?

              attr_def = attributes[elem_rule.to]
              next unless attr_def

              # TYPE NAMESPACE INTEGRATION
              # Store TypeNamespace::Reference for lazy resolution
              if attr_def
                ref = TypeNamespace::Reference.new(attr_def, elem_rule, :element)
                needs.add_type_ref(ref)
              end

              child_type = attr_def.type(@register)
              next unless child_type
              next unless child_type.respond_to?(:<) &&
                child_type < Lutaml::Model::Serialize

              # Get child mapping
              child_mapping = child_type.mappings_for(:xml)
              next unless child_mapping
              next unless child_mapping.mappings_imported

              # Get child instance
              child_instance = if element && element.respond_to?(elem_rule.to)
                                element.send(elem_rule.to)
                              end

              # Handle collections and arrays
              if child_instance.is_a?(Array) || child_instance.is_a?(Lutaml::Model::Collection)
                instances = child_instance.is_a?(Lutaml::Model::Collection) ? child_instance.collection : child_instance
                # Collect needs from all instances and merge
                merged_needs = NamespaceNeeds.new
                instances.each do |item|
                  child_options = { mapper_class: child_type }
                  item_needs = collect_internal(item, child_mapping, **child_options)
                  merged_needs.merge(item_needs)
                end
                child_needs = merged_needs
              else
                # Single instance - collect normally
                child_options = { mapper_class: child_type }
                child_needs = collect_internal(child_instance, child_mapping, **child_options)
              end

              needs.add_child(elem_rule.to, child_needs)

              # Bubble up child namespace requirements
              merge_namespace_needs(needs, child_needs)
            end
          ensure
            # Pop from call stack when done analyzing this type
            call_stack = Thread.current[:namespace_collector_call_stack]
            call_stack.pop if mapper_class && call_stack
          end

          needs
        end

        # Collect namespace needs from XmlDataModel::XmlElement tree
        #
        # @param element [XmlDataModel::XmlElement] the XmlElement to collect from
        # @param mapping [Xml::Mapping] the XML mapping for context
        # @param needs [NamespaceNeeds] the needs structure to populate
        # @param options [Hash] additional options including mapper_class
        # @return [NamespaceNeeds] populated namespace needs
        def collect_from_xml_element(element, mapping, needs, **options)
          # Collect this element's namespace
          if element.namespace_class
            validate_namespace_class(element.namespace_class)
            track_namespace(needs, element.namespace_class, :elements)
          end

          # Collect attribute namespaces
          element.attributes.each do |attr|
            if attr.namespace_class
              validate_namespace_class(attr.namespace_class)
              track_namespace(needs, attr.namespace_class, :attributes)
            end
          end

          # CRITICAL: Collect Type references from mapping
          # Get mapper_class from options (passed from adapter)
          mapper_class = options[:mapper_class]
          attributes = mapper_class&.respond_to?(:attributes) ? mapper_class.attributes : {}

          if attributes.any?
            # ✅ INSTANCE-AWARE FIX: Build set of actual attribute names
            actual_attr_names = Set.new(element.attributes.map(&:name))

            # Collect Type refs for XML attributes (instance-aware)
            mapping.attributes.each do |attr_rule|
              next unless attr_rule.attribute?
              next if attr_rule.to.nil?

              # ✅ FIX: Skip if attribute not present in actual XmlElement
              next unless actual_attr_names.include?(attr_rule.name.to_s)

              attr_def = attributes[attr_rule.to]
              if attr_def
                ref = TypeNamespace::Reference.new(attr_def, attr_rule, :attribute)
                needs.add_type_ref(ref)
              end
            end

            # Collect Type refs for XML elements (always collect for structure)
            mapping.elements.each do |elem_rule|
              attr_def = attributes[elem_rule.to]
              if attr_def
                # Add Type ref for this element
                ref = TypeNamespace::Reference.new(attr_def, elem_rule, :element)
                needs.add_type_ref(ref)

                # ✅ CRITICAL: Don't recursively collect Type refs from child models
                # Child XmlElements will be collected when we traverse tree below
                # This prevents bubbling child Type attributes to parent
              end
            end
          end

          # Collect namespace_scope configuration from mapping
          if mapping.respond_to?(:namespace_scope_config) && mapping.namespace_scope_config&.any?
            mapping.namespace_scope_config.each do |cfg|
              config = NamespaceScopeConfig.new(cfg[:namespace], cfg[:declare] || :auto)
              needs.add_namespace_scope_config(config)
            end
          end

          # Recursively collect from children in XmlElement tree
          element.children.each do |child|
            if child.is_a?(Lutaml::Model::XmlDataModel::XmlElement)
              # ✅ FIX: Match child XmlElement to its corresponding element rule
              # to get the correct child mapping
              child_name = child.name
              matching_rule = mapping.elements.find { |rule| rule.name.to_s == child_name }

              if matching_rule && attributes.any?
                # Get child's mapper_class and mapping
                attr_def = attributes[matching_rule.to]
                if attr_def
                  child_type = attr_def.type(@register)
                  if child_type && child_type.respond_to?(:<) && child_type < Lutaml::Model::Serialize
                    child_mapping = child_type.mappings_for(:xml)
                    if child_mapping
                      # Recursively collect with child's mapping
                      child_needs = NamespaceNeeds.new
                      child_options = options.merge(mapper_class: child_type)
                      collect_from_xml_element(child, child_mapping, child_needs, **child_options)

                      # Store as child and merge
                      needs.add_child(matching_rule.to, child_needs)
                      merge_namespace_needs(needs, child_needs)
                    end
                  else
                    # ✅ BUG FIX (Session 249): For primitive types or non-Serialize types,
                    # collect namespace directly from XmlElement itself
                    # This fixes namespace propagation for primitive children like :string
                    if child.namespace_class && child.namespace_class != :blank
                      track_namespace(needs, child.namespace_class, :elements)
                    end
                  end
                end
              else
                # No matching rule - collect without mapping context
                child_needs = NamespaceNeeds.new
                collect_from_xml_element(child, mapping, child_needs, **options)
                merge_namespace_needs(needs, child_needs)
              end
            end
          end

          needs
        end
      end
    end
  end
end
