# frozen_string_literal: true

require "set"
require_relative "../utils"

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
          # =====================
          # Prevents infinite recursion when analyzing types (element == nil mode)
          #
          # SCENARIO: Type A references Type B, Type B references Type A
          # WITHOUT: Stack overflow during recursive collect() calls
          # WITH: Return empty_needs when revisiting already-analyzed type
          #
          # NOTE: Only used during type analysis (element is nil)
          # Actual instances don't need this - they're finite data structures
          @visited_types = Set.new
        end

        # Collect namespace needs for an element and its descendants
        #
        # @param element [Object] the model instance (can be nil for type analysis)
        # @param mapping [Xml::Mapping] the XML mapping for this element
        # @param options [Hash] additional options including mapper_class for recursive calls
        # @return [Hash] namespace needs structure
        def collect(element, mapping, **options)
          needs = {
            namespaces: {},      # String key (from to_key) => { ns_object: XmlNamespace CLASS, used_in: Set[:elements, :attributes], children_use: Set[ChildNS] }
            children: {},        # Child element => child needs
            type_namespaces: {}, # Attribute name => XmlNamespace CLASS (element-local only)
            type_namespace_classes: Set.new, # Set of XmlNamespace CLASSes that are Type namespaces (bubbles up)
            type_attribute_namespaces: Set.new, # Set of XmlNamespace CLASSes used for XML ATTRIBUTES (must use prefix format)
            type_element_namespaces: Set.new, # Set of XmlNamespace CLASSes used for XML ELEMENTS (can use default or prefix format)
          }

          # Get mapper_class from element or from options (for recursive calls)
          mapper_class = element&.class || options&.dig(:mapper_class)

          # Prevent infinite recursion for type analysis (when element is nil)
          # When collecting from actual instance (element not nil), skip this check
          # Instances are finite - only type graphs can be circular
          if element.nil? && mapper_class
            return empty_needs if @visited_types.include?(mapper_class)

            @visited_types << mapper_class
          end

          attributes = mapper_class.respond_to?(:attributes) ? mapper_class.attributes : {}

          # ==================================================================
          # PHASE 1: OWN NAMESPACE COLLECTION (for non-type-only models)
          # ==================================================================
          # TYPE-ONLY MODELS: No element_name means no root element wrapper
          # BUT we still need to collect namespace needs for their CHILDREN
          # Skip only the own namespace collection, not child collection
          unless mapping.no_element?
            # Collect own element namespace (only for non-type-only models)
            if mapping.namespace_class
              validate_namespace_class(mapping.namespace_class)
              track_namespace(needs, mapping.namespace_class, :elements)
            end

            # ==================================================================
            # PHASE 2: XML ATTRIBUTE NAMESPACE COLLECTION
            # ==================================================================
            # Collect XML attribute namespaces (only for non-type-only models)
            mapping.attributes.each do |attr_rule|
              next unless attr_rule.attribute?
              next if attr_rule.to.nil?  # Guard against nil attribute mapping

              # Skip if we can't resolve attributes
              next unless attributes&.any?

              attr_def = attributes[attr_rule.to]

              # INSTANCE-AWARE COLLECTION:
              # If we have an actual element instance, only collect namespaces
              # for attributes that are actually set (not nil/uninitialized)
              # During type analysis (element == nil), collect all potential attributes
              if element
                value = element.send(attr_rule.to) if element.respond_to?(attr_rule.to)
                # Skip unset attributes during instance serialization
                next if value.nil? || Utils.uninitialized?(value)
              end
              # During type analysis, collect all to understand potential namespace needs

              # Resolve attribute namespace
              ns_class = nil
              if attr_rule.namespace_set?
                # Explicit namespace on attribute rule
                ns_class = attr_rule.namespace_class || mapping.namespace_class
              elsif attr_rule.namespace_class
                ns_class = attr_rule.namespace_class
              elsif attr_def
                # TYPE NAMESPACE INTEGRATION
                # ==========================
                # Check if attribute's type (Type::Value subclass) declares a namespace
                #
                # EXAMPLE: EmailType < Type::String with xml_namespace EmailNamespace
                # RESULT: XML attribute gets EmailNamespace prefix automatically
                #
                # WHY: Type-level namespaces apply to the serialized value's format
                # Allows email addresses, phone numbers, etc. to live in their own namespace
                #
                # KEY CLASSES:
                # - Type::Value.xml_namespace() - declares namespace for Value type
                # - Attribute.type_namespace_class() - retrieves Type's namespace
                type_ns_class = attr_def.type_namespace_class(@register)
                if type_ns_class
                  ns_class = type_ns_class
                  # Track that this attribute uses a Type namespace
                  needs[:type_namespaces][attr_rule.to] = type_ns_class
                  # Also track the class itself so it can bubble up
                  needs[:type_namespace_classes] << type_ns_class
                  # CRITICAL: Mark as XML attribute Type namespace (must use prefix format)
                  needs[:type_attribute_namespaces] << type_ns_class
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
            # NOTE: namespace_scope namespaces are collected here
            # They are handled by DeclarationPlanner based on declare mode:
            # - declare: :always -> always declare
            # - declare: :auto -> only declare if used (in needs)

            # Collect namespace_scope configuration (separate from used namespaces)
            # These are preserved with their declare modes for DeclarationPlanner
            if mapping.namespace_scope_config&.any?
              needs[:namespace_scope_configs] = mapping.namespace_scope_config
            end
          end

          # ==================================================================
          # PHASE 4: ELEMENT NAMESPACE COLLECTION & RECURSION
          # ==================================================================
          # Recurse to child elements
          mapping.elements.each do |elem_rule|
            # Collect explicit element namespace if set
            if elem_rule.namespace_set? && elem_rule.namespace_class
              validate_namespace_class(elem_rule.namespace_class)
              track_namespace(needs, elem_rule.namespace_class, :elements)
            end

            # Skip if we can't resolve attributes
            next unless attributes&.any?

            attr_def = attributes[elem_rule.to]
            next unless attr_def

            # TYPE NAMESPACE INTEGRATION: Check if attribute's type has a namespace
            # This is separate from explicit mapping namespace
            type_ns_class = attr_def.type_namespace_class(@register)
            if type_ns_class && !elem_rule.namespace_set?
              # Only use Type namespace if no explicit mapping namespace was set
              # Explicit mapping namespace takes precedence over Type namespace
              validate_namespace_class(type_ns_class)
              track_namespace(needs, type_ns_class, :elements)

              # Track Type namespace ONLY for Value types, not Model types
              # Models have their own mappings and shouldn't be tracked as Type namespaces
              child_type = attr_def.type(@register)
              is_model = child_type.respond_to?(:<) && child_type < Lutaml::Model::Serialize
              unless is_model
                # This is a Value type (String, Integer, custom Type::Value) with namespace
                needs[:type_namespaces][elem_rule.to] = type_ns_class
                # Also track the class itself so it can bubble up
                needs[:type_namespace_classes] << type_ns_class
                # CRITICAL: Track as element Type namespace (separate from attributes)
                needs[:type_element_namespaces] << type_ns_class
              end
            end

            # NATIVE TYPE NAMESPACE INHERITANCE (Bug Fix #1 from Session 39)
            # ===============================================================
            # Elements with native types (String, Integer, etc.) and no explicit namespace
            # inherit their parent element's namespace
            #
            # BEFORE BUG FIX: <name>value</name> (no namespace)
            # AFTER BUG FIX: <prefix:name>value</prefix:name> (inherits parent)
            #
            # CONDITIONS:
            # 1. Element has no explicit namespace (namespace_set? is false)
            # 2. Element's Type has no namespace (type_ns_class is nil)
            # 3. Element's type is native (String, Integer, not a Model)
            # 4. Parent mapping has a namespace
            #
            # RESULT: Native type element tracked as using parent's namespace
            # This ensures DeclarationPlanner includes parent namespace in plan
            # and serialization applies parent's prefix to the native element
            if !elem_rule.namespace_set? && !type_ns_class
              child_type = attr_def.type(@register)
              is_native = !child_type.respond_to?(:<) || !(child_type < Lutaml::Model::Serialize)

              if is_native && mapping.namespace_class
                # Track parent's namespace as used by this element
                track_namespace(needs, mapping.namespace_class, :elements)
                # Store for serialization to use parent's format
                # This allows adapter to find parent namespace via type_namespaces lookup
                needs[:type_namespaces][elem_rule.to] = mapping.namespace_class
                # Also track as Type namespace class
                needs[:type_namespace_classes] << mapping.namespace_class
              end
            end

            child_type = attr_def.type(@register)
            next unless child_type
            next unless child_type.respond_to?(:<) &&
              child_type < Lutaml::Model::Serialize

            # Get child mapping
            child_mapping = child_type.mappings_for(:xml)
            next unless child_mapping

            # CRITICAL FIX: Pass actual child instance when available
            # This enables instance-aware attribute collection for children too
            # For collections/arrays, collect from all instances and merge
            child_instance = if element && element.respond_to?(elem_rule.to)
                              element.send(elem_rule.to)
                            end

            # Handle collections and arrays specially
            if child_instance.is_a?(Array) || child_instance.is_a?(Lutaml::Model::Collection)
              instances = child_instance.is_a?(Lutaml::Model::Collection) ? child_instance.collection : child_instance
              # Collect needs from all instances and merge
              merged_needs = empty_needs
              instances.each do |item|
                child_options = { mapper_class: child_type }
                item_needs = collect(item, child_mapping, **child_options)
                merge_namespace_needs(merged_needs, item_needs)
              end
              child_needs = merged_needs
            else
              # Single instance - collect normally
              child_options = { mapper_class: child_type }
              child_needs = collect(child_instance, child_mapping, **child_options)
            end

            needs[:children][elem_rule.to] = child_needs

            # Bubble up child namespace requirements
            merge_namespace_needs(needs, child_needs)
          end

          needs
        end

        # Collect namespace needs for a collection of instances
        #
        # @param collection [Collection] the collection instance
        # @param mapping [Xml::Mapping] the XML mapping for the collection
        # @return [Hash] aggregated namespace needs
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
                    merge_namespace_needs(needs, instance_needs)
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
        # @param needs [Hash] the collected namespace needs
        # @param mapping [Xml::Mapping] the root element mapping
        # @return [Boolean] true if prefix is required
        def needs_prefix?(needs, mapping)
          return false unless mapping.namespace_class

          # Look up by string key
          key = mapping.namespace_class.to_key
          ns_entry = needs[:namespaces][key]
          ns_entry && ns_entry[:used_in].include?(:attributes)
        end

        # Get all unique namespaces that need declaration
        #
        # @param needs [Hash] the collected namespace needs
        # @return [Set<Class>] set of XmlNamespace classes
        def all_namespaces(needs)
          all_ns = Set.new
          # Extract ns_object from each namespace entry
          needs[:namespaces].each_value do |ns_entry|
            all_ns << ns_entry[:ns_object]
          end

          # Recursively collect from children
          needs[:children].each_value do |child_needs|
            all_ns.merge(all_namespaces(child_needs))
          end

          all_ns
        end

        # Check if a namespace is used in descendants
        #
        # @param needs [Hash] the collected namespace needs
        # @param namespace_class [Class] the XmlNamespace class to check
        # @return [Boolean] true if namespace is used in tree
        def namespace_used?(needs, namespace_class)
          validate_namespace_class(namespace_class)

          # Look up by string key
          key = namespace_class.to_key
          return true if needs[:namespaces].key?(key)

          needs[:children].each_value do |child_needs|
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

          unless ns_class.is_a?(Class) && ns_class < Lutaml::Model::XmlNamespace
            raise ArgumentError,
                  "Namespace must be XmlNamespace class, got #{ns_class.class}. " \
                  "Same URI + different prefix = different XmlNamespace class."
          end
        end

        # Track namespace usage in needs structure
        #
        # @param needs [Hash] the needs structure
        # @param ns_class [Class] the XmlNamespace class
        # @param usage [Symbol] :elements or :attributes
        def track_namespace(needs, ns_class, usage)
          # Skip tracking for :blank namespace (explicit no namespace)
          return if ns_class == :blank

          key = ns_class.to_key
          needs[:namespaces][key] ||= {
            ns_object: ns_class,
            used_in: Set.new,
            children_use: Set.new,
            children_need_prefix: false,
          }
          needs[:namespaces][key][:used_in] << usage
        end

        # Merge child namespace needs into parent needs
        #
        # CRITICAL: Do NOT merge used_in from children!
        # used_in is element-local only (tracks this element's own usage)
        # children_use tracks that descendants use the namespace
        #
        # CASCADING PREFIX REQUIREMENT:
        # If child uses namespace X in :attributes, parent must provide X with prefix
        # If child already has children_need_prefix for X, parent must also have it
        # Track this via children_need_prefix flag
        #
        # @param parent_needs [Hash] the parent needs structure
        # @param child_needs [Hash] the child needs structure
        def merge_namespace_needs(parent_needs, child_needs)
          child_needs[:namespaces].each do |key, ns_data|
            parent_needs[:namespaces][key] ||= {
              ns_object: ns_data[:ns_object],
              used_in: Set.new,
              children_use: Set.new,
              children_need_prefix: false,
            }
            # DON'T merge used_in - that's element-local
            # parent_needs[:namespaces][key][:used_in].merge(ns_data[:used_in])

            # Track that children use this namespace
            parent_needs[:namespaces][key][:children_use] << ns_data[:ns_object]

            # CASCADING PREFIX: If child uses this namespace in attributes OR
            # if child already needs prefix for its children, cascade upward
            if ns_data[:used_in]&.include?(:attributes) || ns_data[:children_need_prefix]
              parent_needs[:namespaces][key][:children_need_prefix] = true
            end
          end

          # CRITICAL FIX: Merge Type namespace CLASSES (not attr_name mappings)
          # This allows DeclarationPlanner to identify which namespaces are Type namespaces
          # when making hoisting decisions based on namespace_scope
          if child_needs[:type_namespace_classes]&.any?
            parent_needs[:type_namespace_classes] ||= Set.new
            parent_needs[:type_namespace_classes].merge(child_needs[:type_namespace_classes])
          end

          # Merge Type attribute namespaces (XML attributes that need prefix format)
          if child_needs[:type_attribute_namespaces]&.any?
            parent_needs[:type_attribute_namespaces] ||= Set.new
            parent_needs[:type_attribute_namespaces].merge(child_needs[:type_attribute_namespaces])
          end

          # Merge Type element namespaces (XML elements that can use default or prefix format)
          if child_needs[:type_element_namespaces]&.any?
            parent_needs[:type_element_namespaces] ||= Set.new
            parent_needs[:type_element_namespaces].merge(child_needs[:type_element_namespaces])
          end
        end

        # Return empty needs structure for type-only models
        #
        # @return [Hash] empty namespace needs
        def empty_needs
          {
            namespaces: {},
            children: {},
            namespace_scope_configs: nil,
            type_namespaces: {},
            type_namespace_classes: Set.new,
            type_attribute_namespaces: Set.new,
            type_element_namespaces: Set.new,
          }
        end
      end
    end
  end
end
