# frozen_string_literal: true

require_relative "../transformation"
require_relative "../compiled_rule"
require_relative "../xml_data_model"

module Lutaml
  module Model
    module Xml
      # XML-specific transformation implementation.
      #
      # Transforms model instances into XmlElement trees without
      # triggering type resolution or imports during transformation.
      class Transformation < Lutaml::Model::Transformation
        private

        # Compile XML mapping DSL into pre-compiled rules
        #
        # @param mapping_dsl [Xml::Mapping] The XML mapping to compile
        # @return [Array<CompiledRule>] Array of compiled transformation rules
        def compile_rules(mapping_dsl)
          return [] unless mapping_dsl

          rules = []

          # Compile element mappings
          mapping_dsl.elements.each do |mapping_rule|
            rule = compile_element_rule(mapping_rule)
            rules << rule if rule
          end

          # Compile attribute mappings
          mapping_dsl.attributes.each do |mapping_rule|
            rule = compile_attribute_rule(mapping_rule)
            rules << rule if rule
          end

          # Compile content mapping if present
          if mapping_dsl.content_mapping
            rule = compile_content_rule(mapping_dsl.content_mapping)
            rules << rule if rule
          end

          # Compile raw mapping (map_all directive) if present
          if mapping_dsl.raw_mapping
            rule = compile_raw_rule(mapping_dsl.raw_mapping)
            rules << rule if rule
          end

          # Add a pseudo-rule for root namespace if present
          # This ensures root namespace is included in all_namespaces
          if mapping_dsl.namespace_class
            rules << CompiledRule.new(
              attribute_name: :__root_namespace__,
              serialized_name: "__root__",
              namespace_class: mapping_dsl.namespace_class,
              mapping_type: :root_namespace
            )
          end

          rules.compact
        end

        # Compile an element mapping rule
        #
        # @param mapping_rule [Xml::MappingRule] The mapping rule to compile
        # @return [CompiledRule, nil] Compiled rule or nil
        def compile_element_rule(mapping_rule)
          attr_name = mapping_rule.to
          return nil unless attr_name

          # Handle delegated attributes
          if mapping_rule.delegate
            delegate_target = mapping_rule.delegate

            # Get the delegate attribute from model class
            delegate_attr = model_class.attributes(register&.id)&.[](delegate_target)
            return nil unless delegate_attr

            # Get the delegated class type
            delegate_class = delegate_attr.type(register&.id)
            return nil unless delegate_class.respond_to?(:attributes)

            # Get the actual attribute from the delegated class
            attr = delegate_class.attributes(register&.id)&.[](attr_name)
            return nil unless attr

            # Get attribute type
            attr_type = attr.type(register&.id)

            # Build child transformation for nested models
            child_transformation = if attr_type.is_a?(Class) &&
                                      attr_type < Lutaml::Model::Serialize
                                     build_child_transformation(attr_type)
                                   end

            # Build collection info
            collection_info = if attr.collection?
                                { range: attr.options[:collection] }
                              end

            # Extract namespace class
            # Priority:
            # 1. Explicit namespace on mapping rule
            # 2. Type xml_namespace (for types with namespace)
            namespace_class = mapping_rule.namespace_class
            if !namespace_class && attr_type.respond_to?(:xml_namespace)
              namespace_class = attr_type.xml_namespace
            end

            # Build value transformer
            value_transformer = build_value_transformer(mapping_rule, attr)

            # Access value_map instance variable directly
            value_map = mapping_rule.instance_variable_get(:@value_map)

            return CompiledRule.new(
              attribute_name: attr_name,
              serialized_name: mapping_rule.name.to_s,
              attribute_type: attr_type,
              child_transformation: child_transformation,
              value_transformer: value_transformer,
              collection_info: collection_info,
              namespace_class: namespace_class,
              mapping_type: :element,
              cdata: mapping_rule.cdata,
              mixed_content: mapping_rule.mixed_content?,
              raw: attr.raw?,
              render_nil: mapping_rule.render_nil,
              render_default: mapping_rule.render_default,
              render_empty: mapping_rule.render_empty,
              value_map: value_map,
              polymorphic: mapping_rule.polymorphic,
              delegate_from: delegate_target  # Store delegation info
            )
          end

          # Get attribute definition from model class (non-delegated)
          attr = model_class.attributes(register&.id)&.[](attr_name)
          return nil unless attr

          # Get attribute type
          attr_type = attr.type(register&.id)

          # Build child transformation for nested models
          child_transformation = if attr_type.is_a?(Class) &&
                                    attr_type < Lutaml::Model::Serialize
                                   build_child_transformation(attr_type)
                                 end

          # Build collection info
          collection_info = if attr.collection?
                              { range: attr.options[:collection] }
                            end

          # Extract namespace class
          # Priority:
          # 1. Explicit namespace on mapping rule
          # 2. Type xml_namespace (for types with namespace)
          namespace_class = mapping_rule.namespace_class
          if !namespace_class && attr_type.respond_to?(:xml_namespace)
            namespace_class = attr_type.xml_namespace
          end

          # Build value transformer
          value_transformer = build_value_transformer(mapping_rule, attr)

          # Access value_map instance variable directly
          value_map = mapping_rule.instance_variable_get(:@value_map)

          CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: mapping_rule.name.to_s,
            attribute_type: attr_type,
            child_transformation: child_transformation,
            value_transformer: value_transformer,
            collection_info: collection_info,
            namespace_class: namespace_class,
            mapping_type: :element,
            cdata: mapping_rule.cdata,
            mixed_content: mapping_rule.mixed_content?,
            raw: attr.raw?,
            render_nil: mapping_rule.render_nil,
            render_default: mapping_rule.render_default,
            render_empty: mapping_rule.render_empty,
            value_map: value_map,
            polymorphic: mapping_rule.polymorphic
          )
        end

        # Compile an attribute mapping rule
        #
        # @param mapping_rule [Xml::MappingRule] The mapping rule to compile
        # @return [CompiledRule, nil] Compiled rule or nil
        def compile_attribute_rule(mapping_rule)
          attr_name = mapping_rule.to
          return nil unless attr_name

          # Handle delegated attributes
          if mapping_rule.delegate
            delegate_target = mapping_rule.delegate

            # Get the delegate attribute from model class
            delegate_attr = model_class.attributes(register&.id)&.[](delegate_target)
            return nil unless delegate_attr

            # Get the delegated class type
            delegate_class = delegate_attr.type(register&.id)
            return nil unless delegate_class.respond_to?(:attributes)

            # Get the actual attribute from the delegated class
            attr = delegate_class.attributes(register&.id)&.[](attr_name)
            return nil unless attr

            # Get attribute type
            attr_type = attr.type(register&.id)

            # Extract namespace class
            # Priority:
            # 1. Explicit namespace on mapping rule
            # 2. Type xml_namespace (for types with namespace)
            namespace_class = mapping_rule.namespace_class
            if !namespace_class && attr_type.respond_to?(:xml_namespace)
              namespace_class = attr_type.xml_namespace
            end

            # Build value transformer
            value_transformer = build_value_transformer(mapping_rule, attr)

            # Access value_map instance variable directly
            value_map = mapping_rule.instance_variable_get(:@value_map)

            return CompiledRule.new(
              attribute_name: attr_name,
              serialized_name: mapping_rule.name.to_s,
              attribute_type: attr_type,
              value_transformer: value_transformer,
              namespace_class: namespace_class,
              mapping_type: :attribute,
              render_nil: mapping_rule.render_nil,
              render_default: mapping_rule.render_default,
              render_empty: mapping_rule.render_empty,
              value_map: value_map,
              as_list: mapping_rule.as_list,
              delimiter: mapping_rule.delimiter,
              delegate_from: delegate_target  # Store delegation info
            )
          end

          # Get attribute definition from model class (non-delegated)
          attr = model_class.attributes(register&.id)&.[](attr_name)
          return nil unless attr

          # Get attribute type
          attr_type = attr.type(register&.id)

          # Extract namespace class
          # Priority:
          # 1. Explicit namespace on mapping rule
          # 2. Type xml_namespace (for types with namespace)
          namespace_class = mapping_rule.namespace_class
          if !namespace_class && attr_type.respond_to?(:xml_namespace)
            namespace_class = attr_type.xml_namespace
          end

          # Build value transformer
          value_transformer = build_value_transformer(mapping_rule, attr)

          # Access value_map instance variable directly
          value_map = mapping_rule.instance_variable_get(:@value_map)

          CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: mapping_rule.name.to_s,
            attribute_type: attr_type,
            value_transformer: value_transformer,
            namespace_class: namespace_class,
            mapping_type: :attribute,
            render_nil: mapping_rule.render_nil,
            render_default: mapping_rule.render_default,
            render_empty: mapping_rule.render_empty,
            value_map: value_map,
            as_list: mapping_rule.as_list,
            delimiter: mapping_rule.delimiter
          )
        end

        # Compile a content mapping rule
        #
        # @param mapping_rule [Xml::MappingRule] The content mapping rule
        # @return [CompiledRule, nil] Compiled rule or nil
        def compile_content_rule(mapping_rule)
          attr_name = mapping_rule.to
          return nil unless attr_name

          # Get attribute definition
          attr = model_class.attributes(register&.id)&.[](attr_name)
          return nil unless attr

          # Build value transformer
          value_transformer = build_value_transformer(mapping_rule, attr)

          # Access value_map instance variable directly
          value_map = mapping_rule.instance_variable_get(:@value_map)

          CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: nil, # Content has no name
            attribute_type: attr.type(register&.id),
            value_transformer: value_transformer,
            mapping_type: :content,
            cdata: mapping_rule.cdata,
            mixed_content: mapping_rule.mixed_content?,
            render_nil: mapping_rule.render_nil,
            render_default: mapping_rule.render_default,
            render_empty: mapping_rule.render_empty,
            value_map: value_map
          )
        end

        # Compile a raw mapping rule (map_all directive)
        #
        # @param mapping_rule [Xml::MappingRule] The raw mapping rule
        # @return [CompiledRule, nil] Compiled rule or nil
        def compile_raw_rule(mapping_rule)
          attr_name = mapping_rule.to
          return nil unless attr_name

          # Get attribute definition
          attr = model_class.attributes(register&.id)&.[](attr_name)
          return nil unless attr

          # Build value transformer
          value_transformer = build_value_transformer(mapping_rule, attr)

          # Access value_map instance variable directly
          value_map = mapping_rule.instance_variable_get(:@value_map)

          CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: nil, # Raw content has no element name
            attribute_type: attr.type(register&.id),
            value_transformer: value_transformer,
            mapping_type: :raw,
            render_nil: mapping_rule.render_nil,
            render_default: mapping_rule.render_default,
            render_empty: mapping_rule.render_empty,
            value_map: value_map,
            custom_methods: mapping_rule.custom_methods
          )
        end

        # Build child transformation for nested model
        #
        # @param type_class [Class] The nested model class
        # @return [Transformation, nil] Child transformation or nil
        def build_child_transformation(type_class)
          return nil unless type_class.respond_to?(:transformation_for)

          type_class.transformation_for(:xml, register)
        end

        # Build value transformer from mapping rule and attribute
        #
        # @param mapping_rule [Xml::MappingRule] The mapping rule
        # @param attr [Attribute] The attribute definition
        # @return [Proc, Hash, nil] Value transformer
        def build_value_transformer(mapping_rule, attr)
          # Mapping-level transform takes precedence
          mapping_transform = mapping_rule.transform

          # Try to get attribute-level transform
          # The transform can be in attr.options[:transform] or attr.transform
          attr_transform = if attr.respond_to?(:transform)
                             attr.transform
                           elsif attr.options
                             attr.options[:transform]
                           end

          # Return mapping transform if present and non-empty
          if mapping_transform && !mapping_transform.empty?
            return mapping_transform
          end

          # Return attribute transform if present
          if attr_transform && !attr_transform.empty?
            return attr_transform
          end

          nil
        end

        public

        # Transform a model instance into XmlElement tree
        #
        # @param model_instance [Object] The model instance to transform
        # @param options [Hash] Transformation options
        # @return [XmlDataModel::XmlElement] The root XML element
        def transform(model_instance, options = {})
          # Get root element name from mapping
          mapping = model_class.mappings_for(:xml, register&.id)
          root_name = mapping.root_element || model_class.name.split("::").last

          # Get root namespace
          root_namespace = mapping.namespace_class

          # Check if this root element needs xmlns="" due to parent context
          # This handles nested models where parent uses default format and child has no namespace
          parent_uses_default_ns = options[:parent_uses_default_ns]
          needs_xmlns_blank = parent_uses_default_ns && !root_namespace

          # Create root element
          root = XmlDataModel::XmlElement.new(root_name, root_namespace)

          # Mark that this element needs xmlns="" (for DeclarationPlanner)
          if needs_xmlns_blank
            root.instance_variable_set(:@needs_xmlns_blank, true)
          end

          # Store namespace_scope_config for hoisting support
          # This allows adapters to hoist namespaces to root element
          namespace_scope_config = mapping.namespace_scope_config || []
          root.instance_variable_set(:@namespace_scope_config, namespace_scope_config)

          # Handle schema_location if present
          # SchemaLocation is metadata, not a mapped attribute, so handle it specially
          # Two cases: SchemaLocation object (programmatic) or @raw_schema_location string (from parsing)

          # Case 1: SchemaLocation object (programmatic creation)
          if model_instance.respond_to?(:schema_location) && model_instance.schema_location
            schema_loc = model_instance.schema_location
            if schema_loc.respond_to?(:to_xml_attributes)
              # Get xmlns:xsi and xsi:schemaLocation attributes
              # These are already fully qualified with prefixes, so add them as literal names
              schema_attrs = schema_loc.to_xml_attributes

              # Add each as an XmlAttribute to root element
              # Pass nil as namespace_class because attribute names are already prefixed
              schema_attrs.each do |attr_name, attr_value|
                attr = XmlDataModel::XmlAttribute.new(attr_name, attr_value, nil)
                root.add_attribute(attr)
              end
            end
          # Case 2: @raw_schema_location string (from parsing/round-trip)
          elsif model_instance.instance_variable_defined?(:@raw_schema_location)
            raw_schema_loc = model_instance.instance_variable_get(:@raw_schema_location)
            if raw_schema_loc && !raw_schema_loc.empty?
              # Add xmlns:xsi namespace declaration
              xsi_ns_attr = XmlDataModel::XmlAttribute.new(
                "xmlns:xsi",
                "http://www.w3.org/2001/XMLSchema-instance",
                nil
              )
              root.add_attribute(xsi_ns_attr)

              # Add xsi:schemaLocation attribute with raw value
              schema_loc_attr = XmlDataModel::XmlAttribute.new(
                "xsi:schemaLocation",
                raw_schema_loc,
                nil
              )
              root.add_attribute(schema_loc_attr)
            end
          end

          # Apply each compiled rule (with filtering support)
          compiled_rules.each do |rule|
            # Check if this rule should be applied based on only/except options
            next unless valid_mapping?(rule, options)

            apply_rule(root, rule, model_instance, options)
          end

          root
        end

        private

        # Apply a single transformation rule
        #
        # @param parent [XmlDataModel::XmlElement] Parent element
        # @param rule [CompiledRule] The rule to apply
        # @param model_instance [Object] The model instance
        # @param options [Hash] Transformation options
        def apply_rule(parent, rule, model_instance, options)
          # Skip pseudo-rules like root_namespace
          return if rule.option(:mapping_type) == :root_namespace

          # Get attribute value - handle delegation
          value = if rule.option(:delegate_from)
                    # Extract value from delegated object
                    delegate_obj = model_instance.public_send(rule.option(:delegate_from))
                    delegate_obj&.public_send(rule.attribute_name)
                  else
                    # Extract value normally from model instance
                    model_instance.public_send(rule.attribute_name)
                  end

          # Handle render options and value_map
          # For delegated attributes, check if delegate object is using default
          should_skip = if rule.option(:delegate_from)
                          delegate_obj = model_instance.public_send(rule.option(:delegate_from))
                          should_skip_delegated_value?(value, rule, delegate_obj)
                        else
                          should_skip_value?(value, rule, model_instance)
                        end
          return if should_skip

          # Apply export transformation if present BEFORE any other processing
          if rule.value_transformer
            value = rule.transform_value(value, :export)
          end

          # Handle based on rule type
          case rule.option(:mapping_type)
          when :element
            apply_element_rule(parent, rule, value, options)
          when :attribute
            apply_attribute_rule(parent, rule, value, options)
          when :content
            apply_content_rule(parent, rule, value, options)
          when :raw
            apply_raw_rule(parent, rule, value, options)
          end
        end

        # Check if value should be skipped based on render options
        #
        # @param value [Object] The value to check
        # @param rule [CompiledRule] The rule
        # @param model_instance [Object] The model instance
        # @return [Boolean] true if should skip
        def should_skip_value?(value, rule, model_instance)
          attr_name = rule.attribute_name

          # Check render_nil and render_empty shortcuts FIRST
          # This ensures mutated collections with default values are still serialized
          if value.nil?
            # Check render_nil option (convenience shortcut)
            render_nil = rule.option(:render_nil)
            return true if render_nil == :omit
            return false if render_nil == true  # true means DO render nil
            return false if render_nil == :as_nil  # :as_nil means DO render nil
            return false if render_nil == :as_empty  # :as_empty means render as empty collection

            # Fall back to value_map
            value_map = rule.option(:value_map) || {}
            return value_map[:nil] == :omit
          elsif Lutaml::Model::Utils.empty?(value)
            # Check render_empty option (convenience shortcut)
            render_empty = rule.option(:render_empty)
            return true if render_empty == :omit
            return false if render_empty == true  # true means DO render empty
            return false if render_empty == :as_nil  # :as_nil means DO render with xsi:nil
            return false if render_empty == :as_blank  # :as_blank means DO render blank element

            # For false or unset, default to skipping empty values (legacy behavior)
            value_map = rule.option(:value_map) || {}
            return value_map[:empty] == :omit
          elsif Lutaml::Model::Utils.uninitialized?(value)
            value_map = rule.option(:value_map) || {}
            return value_map[:omitted] == :omit || true # Default: omit uninitialized
          end

          # Handle boolean value_map for true/false values
          # Check if this is a boolean type with custom value_map
          if value.is_a?(TrueClass) || value.is_a?(FalseClass)
            value_map = rule.option(:value_map) || {}
            # Convert boolean to symbol key for hash access
            boolean_key = value ? :true : :false
            if value_map[:to] && value_map[:to][boolean_key]
              mapped_value = value_map[:to][boolean_key]
              return true if mapped_value == :omitted
            end
          end

          # Skip if using default and render_default is false
          # But for collections, check if they were mutated (non-empty)
          if model_instance.respond_to?(:using_default?) &&
             model_instance.using_default?(attr_name) &&
             !rule.option(:render_default)
            # For collections: if mutated to non-empty, serialize them
            # For scalars: skip if using default
            if rule.collection?
              return false unless Lutaml::Model::Utils.empty?(value)
            else
              return true
            end
          end

          false
        end

        # Check if delegated value should be skipped
        #
        # @param value [Object] The value to check
        # @param rule [CompiledRule] The rule
        # @param delegate_obj [Object] The delegated object instance
        # @return [Boolean] true if should skip
        def should_skip_delegated_value?(value, rule, delegate_obj)
          return true if delegate_obj.nil?

          attr_name = rule.attribute_name

          # Check render_nil and render_empty shortcuts FIRST
          # This ensures mutated collections with default values are still serialized
          if value.nil?
            # Check render_nil option (convenience shortcut)
            render_nil = rule.option(:render_nil)
            return true if render_nil == :omit
            return false if render_nil == true  # true means DO render nil
            return false if render_nil == :as_nil  # :as_nil means DO render nil
            return false if render_nil == :as_empty  # :as_empty means render as empty collection

            # Fall back to value_map
            value_map = rule.option(:value_map) || {}
            return value_map[:nil] == :omit
          elsif Lutaml::Model::Utils.empty?(value)
            # Check render_empty option (convenience shortcut)
            render_empty = rule.option(:render_empty)
            return true if render_empty == :omit
            return false if render_empty == true  # true means DO render empty
            return false if render_empty == :as_nil  # :as_nil means DO render with xsi:nil
            return false if render_empty == :as_blank  # :as_blank means DO render blank element

            # For false or unset, default to skipping empty values (legacy behavior)
            value_map = rule.option(:value_map) || {}
            return value_map[:empty] == :omit
          elsif Lutaml::Model::Utils.uninitialized?(value)
            value_map = rule.option(:value_map) || {}
            return value_map[:omitted] == :omit || true # Default: omit uninitialized
          end

          # Handle boolean value_map for true/false values
          # Check if this is a boolean type with custom value_map
          if value.is_a?(TrueClass) || value.is_a?(FalseClass)
            value_map = rule.option(:value_map) || {}
            # Convert boolean to symbol key for hash access
            boolean_key = value ? :true : :false
            if value_map[:to] && value_map[:to][boolean_key]
              mapped_value = value_map[:to][boolean_key]
              return true if mapped_value == :omitted
            end
          end

          # Skip if delegate object is using default and render_default is false
          # But for collections, check if they were mutated (non-empty)
          if delegate_obj.respond_to?(:using_default?) &&
             delegate_obj.using_default?(attr_name) &&
             !rule.option(:render_default)
            # For collections: if mutated to non-empty, serialize them
            # For scalars: skip if using default
            if rule.collection?
              return false unless Lutaml::Model::Utils.empty?(value)
            else
              return true
            end
          end

          false
        end

        # Apply an element rule
        #
        # @param parent [XmlDataModel::XmlElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options
        def apply_element_rule(parent, rule, value, options)
          # Extract parent's namespace info for element_form_default inheritance
          parent_ns_class = parent.namespace_class
          parent_element_form_default = parent_ns_class&.element_form_default

          # Merge parent context into options
          child_options = options.merge(
            parent_namespace_class: parent_ns_class,
            parent_element_form_default: parent_element_form_default
          )

          if rule.collection?
            # Handle collection
            # Special case for render_nil with nil collections
            if value.nil?
              render_nil = rule.option(:render_nil)
              if render_nil == :as_nil
                # Create single element with xsi:nil="true"
                element = create_element_for_value(rule, nil, child_options)
                parent.add_child(element) if element
              elsif render_nil == :as_blank
                # Create blank element (empty string, no xsi:nil)
                element = create_element_for_value(rule, "", child_options)
                parent.add_child(element) if element
              else
                # Other modes: omit nil collections (skip them)
                Array(value).each do |item|
                  element = create_element_for_value(rule, item, child_options)
                  parent.add_child(element) if element
                end
              end
            elsif Lutaml::Model::Utils.empty?(value)
              # Handle empty collections based on render_empty option
              render_empty = rule.option(:render_empty)
              if render_empty == :as_nil
                # Create single element with xsi:nil="true"
                element = create_element_for_value(rule, nil, child_options)
                parent.add_child(element) if element
              elsif render_empty == :as_blank
                # Create blank element (empty string content)
                element = create_element_for_value(rule, "", child_options)
                parent.add_child(element) if element
              else
                # For true, :as_empty, or unset: skip empty collections
                # (Array.each on empty array does nothing, so this skips)
                Array(value).each do |item|
                  element = create_element_for_value(rule, item, child_options)
                  parent.add_child(element) if element
                end
              end
            else
              Array(value).each do |item|
                element = create_element_for_value(rule, item, child_options)
                parent.add_child(element) if element
              end
            end
          else
            # Handle single value
            element = create_element_for_value(rule, value, child_options)
            parent.add_child(element) if element
          end
        end

        # Create an element for a value
        #
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options
        # @return [XmlDataModel::XmlElement, nil] The created element
        def create_element_for_value(rule, value, options)
          # Check render_nil option - if true, create element even for nil values
          # This allows xsi:nil attribute to be added by the adapter
          if value.nil?
            # Only return nil (skip element) if render_nil is not explicitly set
            # But also check render_empty which can apply to nil collections
            render_nil = rule.option(:render_nil)
            render_empty = rule.option(:render_empty)

            # Create element if render_nil or render_empty option is set
            return nil unless render_nil || render_empty
          end

          # Check if this is a nested model (even if child_transformation is nil due to cycles)
          is_nested_model = rule.attribute_type.is_a?(Class) &&
                           rule.attribute_type < Lutaml::Model::Serialize

          if is_nested_model
            # For polymorphic collections, resolve the actual child class and use its transformation
            # This ensures the correct element name (e.g., "item" not "base_item")
            polymorphic_config = rule.options[:polymorphic]
            is_polymorphic = polymorphic_config && !polymorphic_config.empty?

            actual_class = if is_polymorphic
                             # Inline polymorphic resolution (from Attribute#resolve_polymorphic_class)
                             poly_attr = polymorphic_config[:attribute]
                             poly_class_map = polymorphic_config[:class_map]
                             poly_value = value.send(poly_attr) if poly_attr && value.respond_to?(poly_attr)
                             if poly_value && poly_class_map && (klass_name = poly_class_map[poly_value.to_s])
                               Object.const_get(klass_name)
                             else
                               rule.attribute_type
                             end
                           else
                             rule.attribute_type
                           end

            # Get transformation for the actual class
            # For polymorphic cases, ALWAYS get fresh transformation (don't use cached rule.child_transformation)
            # because it was compiled for the BASE class, not the actual polymorphic class
            child_transformation = if is_polymorphic
                                    actual_class.transformation_for(:xml, register)
                                  else
                                    rule.child_transformation || actual_class.transformation_for(:xml, register)
                                  end

            if child_transformation
              # Transform nested model - this gives us the full element with its own namespace
              # Pass parent's default namespace format for xmlns="" decision on child's root element
              # parent_uses_default_ns = true when parent has namespace and uses default format (no prefix)
              parent_ns_class = options[:parent_namespace_class]
              parent_uses_default_ns = parent_ns_class && !parent_ns_class.prefix_default
              child_options = options.merge(parent_uses_default_ns: parent_uses_default_ns)
              child_element = child_transformation.transform(value, child_options)

              # CRITICAL: Use parent's mapping name, not child's root name
              # When a model is nested, the element name comes from the PARENT's mapping
              # For example: map_element "description", to: :description creates <description> not <WithMapAll>
              if rule.serialized_name != child_element.name
                child_element.instance_variable_set(:@name, rule.serialized_name)
              end

              # Use the child element directly - it already has the correct namespace and structure
              return child_element
            else
              # Fallback: serialize as simple value
              # Determine element namespace with inheritance support
              element_namespace_class = determine_element_namespace(
                rule,
                options[:parent_namespace_class],
                options[:parent_element_form_default]
              )

              element = XmlDataModel::XmlElement.new(
                rule.serialized_name,
                element_namespace_class
              )

              text = serialize_value(value, rule)
              element.text_content = text if text
              return element
            end
          else
            # Simple value (not a nested model)
            # Determine element namespace with inheritance support
            element_namespace_class = determine_element_namespace(
              rule,
              options[:parent_namespace_class],
              options[:parent_element_form_default]
            )

            element = XmlDataModel::XmlElement.new(
              rule.serialized_name,
              element_namespace_class
            )

            # Get the value as text
            text = serialize_value(value, rule)

            # Mark element as nil for xsi:nil rendering when render_nil or render_empty is :as_nil
            # This allows adapters to add xsi:nil="true" attribute
            if value.nil?
              render_nil = rule.option(:render_nil)
              render_empty = rule.option(:render_empty)
              if render_nil == :as_nil || render_empty == :as_nil
                element.instance_variable_set(:@is_nil, true)
              end
            end

            # Return element without text content for nil or empty strings
            # This produces self-closing tags (<items/> instead of <items></items>)
            return element if text.nil? || text.to_s.empty?

            # Handle raw option - content should not be escaped
            if rule.raw
              # Store as raw content for adapter serialization
              # Adapters will check for @raw_content and use add_xml_fragment
              element.instance_variable_set(:@raw_content, text.to_s)
            else
              # Normal text content - will be escaped by adapter
              element.text_content = text
            end

            return element
          end
        end

        # Determine element namespace with MECE priority
        #
        # Priority:
        #   1. Type xml_namespace (explicit type-level namespace)
        #   2. Rule namespace_class (explicit mapping-level namespace)
        #   3. Parent inheritance (element_form_default: :qualified)
        #   4. Blank namespace (no inheritance)
        #
        # @param rule [CompiledRule] The rule
        # @param parent_namespace_class [Class, nil] Parent's namespace class
        # @param parent_element_form_default [Symbol, nil] Parent's element_form_default
        # @return [Class, nil] The namespace class to use
        def determine_element_namespace(rule, parent_namespace_class, parent_element_form_default)
          # Priority 1: Type declares xml_namespace (HIGHEST)
          if rule.attribute_type.respond_to?(:xml_namespace) && rule.attribute_type.xml_namespace
            return rule.attribute_type.xml_namespace
          end

          # Priority 2: Explicit namespace on mapping rule
          if rule.namespace_class
            return rule.namespace_class
          end

          # Priority 3: Inherit parent's namespace (element_form_default: :qualified)
          if parent_element_form_default == :qualified && parent_namespace_class
            return parent_namespace_class
          end

          # Priority 4: Blank namespace (no inheritance)
          nil
        end

        # Apply an attribute rule
        #
        # @param parent [XmlDataModel::XmlElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options
        def apply_attribute_rule(parent, rule, value, options)
          # Serialize value to string
          text = serialize_value(value, rule)
          return unless text

          # Determine attribute namespace - type namespace takes precedence
          attr_namespace_class = if rule.attribute_type.respond_to?(:xml_namespace) && rule.attribute_type.xml_namespace
                                   # Type declares xml_namespace - use it
                                   rule.attribute_type.xml_namespace
                                 else
                                   # Use rule's namespace_class
                                   rule.namespace_class
                                 end

          # Create attribute
          attr = XmlDataModel::XmlAttribute.new(
            rule.serialized_name,
            text,
            attr_namespace_class
          )

          parent.add_attribute(attr)
        end

        # Apply a content rule
        #
        # @param parent [XmlDataModel::XmlElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options
        # Apply a content mapping rule (map_content directive)
        #
        # For mixed content, when value is an Array, each item is added as a
        # separate child text node. For regular content, value is set as text_content.
        #
        # @param parent [XmlDataModel::XmlElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options
        def apply_content_rule(parent, rule, value, options)
          return if value.nil?
          return if Lutaml::Model::Utils.uninitialized?(value)

          # Check if this is mixed content (value is an Array of text strings)
          # The mixed_content flag can be on either the rule or the mapping
          # For content rules, if value is an Array, it's mixed content from parsing
          xml_mapping = model_class.mappings_for(:xml)
          is_mixed = rule.mixed_content || xml_mapping&.mixed_content? || value.is_a?(Array)
          if value.is_a?(Array) && is_mixed
            # For mixed content, interleave text nodes with existing element children
            # The content array has n+1 items for n element children:
            # - content[0] goes before first element
            # - content[1] goes between element[0] and element[1]
            # - ...
            # - content[n] goes after element[n-1]

            # Get existing element children (added by element rules before this content rule)
            existing_children = parent.children.dup

            # Clear children and rebuild with interleaved content
            parent.children.clear

            # Add content[0] before first element (if exists)
            if value[0]
              parent.add_child(value[0].to_s)
            end

            # Interleave remaining content with existing elements
            existing_children.each_with_index do |child, index|
              parent.add_child(child)

              # Add content after this element (if exists)
              content_index = index + 1
              if value[content_index]
                parent.add_child(value[content_index].to_s)
              end
            end
          else
            # For regular content, serialize value and set as text_content
            text = serialize_value(value, rule)
            parent.text_content = text if text
          end
        end

        # Apply a raw mapping rule (map_all directive)
        #
        # Raw content is the entire inner XML as a string, including elements and text.
        # Store it on the parent element so adapters can serialize it as raw XML fragment.
        # Custom methods can still be called by adapters for additional processing.
        #
        # @param parent [XmlDataModel::XmlElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param value [Object] The raw XML content as string
        # @param options [Hash] Options
        def apply_raw_rule(parent, rule, value, options)
          return unless value
          return if value.to_s.empty?

          # Store raw content on parent element for adapter serialization
          # Adapters will check for @raw_content and use add_xml_fragment
          # If custom methods exist, adapters may call them for additional processing
          parent.instance_variable_set(:@raw_content, value.to_s)
        end

        # Check if a mapping rule should be applied based on only/except options
        #
        # @param rule [CompiledRule] The rule to check
        # @param options [Hash] Transformation options (may contain :only, :except)
        # @return [Boolean] true if the rule should be applied
        def valid_mapping?(rule, options)
          only = options[:only]
          except = options[:except]
          name = rule.attribute_name

          (except.nil? || !except.include?(name)) &&
            (only.nil? || only.include?(name))
        end

        # Serialize a value to string
        #
        # @param value [Object] The value to serialize
        # @param rule [CompiledRule] The rule
        # @return [String, nil] Serialized value
        def serialize_value(value, rule)
          return nil if value.nil?
          return nil if Lutaml::Model::Utils.uninitialized?(value)

          # Handle boolean value_map for true: :empty
          # This MUST be checked before the Value type wrapping below
          # When boolean true maps to :empty, serialize as empty string (<Active/>)
          if value.is_a?(TrueClass) || value.is_a?(FalseClass)
            value_map = rule.option(:value_map) || {}
            # Convert boolean to symbol key for hash access
            boolean_key = value ? :true : :false
            if value_map[:to] && value_map[:to][boolean_key]
              mapped_value = value_map[:to][boolean_key]
              return "" if mapped_value == :empty
              # For :omitted, return nil (caller will skip rendering)
              return nil if mapped_value == :omitted
            end
          end

          # Handle as_list and delimiter for array values BEFORE serialization
          # These features convert arrays to delimited strings for XML attributes
          if value.is_a?(Array)
            if rule.option(:as_list) && rule.option(:as_list)[:export]
              value = rule.option(:as_list)[:export].call(value)
            elsif rule.option(:delimiter)
              value = value.join(rule.option(:delimiter))
            end
          end

          # For Reference types, use attribute's serialize method which handles reference_key extraction
          # Check the attribute's unresolved_type to match the condition in Attribute#serialize
          attr = model_class.attributes(register&.id)&.[](rule.attribute_name)
          attr ||= model_class.attributes&.[](rule.attribute_name)

          if attr && attr.unresolved_type == Lutaml::Model::Type::Reference
            return attr.serialize(value, :xml, register&.id, {})
          end

          # For custom Value types with instance methods (to_xml, to_json, etc.)
          # wrap the value and call the instance method
          if rule.attribute_type.respond_to?(:new) && rule.attribute_type < Lutaml::Model::Type::Value
            wrapped_value = rule.attribute_type.new(value)
            if wrapped_value.respond_to?(:to_xml)
              return wrapped_value.to_xml
            end
          end

          # Use type's serialization if available
          if rule.attribute_type.respond_to?(:serialize)
            rule.attribute_type.serialize(value)
          else
            value.to_s
          end
        end
      end
    end
  end
end