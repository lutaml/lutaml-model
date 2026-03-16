# frozen_string_literal: true

module Lutaml
  module Xml
    module TransformationSupport
      # Module for creating XML elements from values.
      #
      # Handles:
      # - Nested model transformation
      # - Polymorphic type resolution
      # - Namespace determination
      # - Simple value serialization
      module ElementBuilder
        include ValueSerializer

        # Create an element for a value
        #
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options including parent context
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @param register [Register, nil] The register
        # @return [::Lutaml::Xml::DataModel::XmlElement, nil] The created element
        def create_element_for_value(rule, value, options, model_class,
register_id, register)
          # Check render_nil option - if true, create element even for nil values
          return nil unless should_create_element_for_nil?(rule, value)

          # Check if this is a nested model (even if child_transformation is nil due to cycles)
          is_nested_model = rule.attribute_type.is_a?(Class) &&
            rule.attribute_type < Lutaml::Model::Serialize

          if is_nested_model
            create_nested_model_element(rule, value, options, register)
          else
            create_simple_value_element(rule, value, options, model_class,
                                        register_id)
          end
        end

        # Determine element namespace with MECE priority
        #
        # Priority:
        #   1. Type xml_namespace (explicit type-level namespace)
        #   2. Rule namespace_class (explicit mapping-level namespace)
        #   3. Form override unqualified (form: :unqualified forces blank namespace)
        #   4. Parent inheritance (element_form_default: :qualified)
        #   5. Form override qualified (form: :qualified forces namespace inheritance)
        #   6. Blank namespace (no inheritance)
        #
        # @param rule [CompiledRule] The rule
        # @param parent_namespace_class [Class, nil] Parent's namespace class
        # @param parent_element_form_default [Symbol, nil] Parent's element_form_default
        # @return [Class, nil] The namespace class to use
        def determine_element_namespace(rule, parent_namespace_class,
parent_element_form_default)
          # Priority 1: Type declares namespace (HIGHEST)
          attr_type = rule.attribute_type
          if attr_type.is_a?(Class) && attr_type <= Lutaml::Model::Type::Value && attr_type.namespace_class
            return attr_type.namespace_class
          end

          # Priority 2: Explicit namespace on mapping rule
          return rule.namespace_class if rule.namespace_class

          # Priority 3: Form override unqualified
          return nil if rule.form == :unqualified

          # Priority 4: Inherit parent's namespace (element_form_default: :qualified)
          if parent_element_form_default == :qualified && parent_namespace_class
            return parent_namespace_class
          end

          # Priority 5: Form override qualified
          return parent_namespace_class if rule.form == :qualified && parent_namespace_class

          # Priority 6: Blank namespace (no inheritance)
          nil
        end

        private

        # Check if element should be created for nil value
        #
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @return [Boolean] true if element should be created
        def should_create_element_for_nil?(rule, value)
          return true unless value.nil?

          value_map = rule.option(:value_map) || {}
          to_map = value_map[:to] || value_map
          mapped_value = to_map[:nil]

          render_nil = rule.option(:render_nil)
          render_empty = rule.option(:render_empty)

          render_nil || render_empty || mapped_value == :nil || mapped_value == :empty
        end

        # Create element for nested model
        #
        # @param rule [CompiledRule] The rule
        # @param value [Object] The model instance
        # @param options [Hash] Options
        # @param register [Register, nil] The register
        # @return [::Lutaml::Xml::DataModel::XmlElement] The created element
        def create_nested_model_element(rule, value, options, register)
          # Resolve polymorphic configuration
          polymorphic_config = rule.options[:polymorphic]
          is_polymorphic = polymorphic_config.is_a?(::Hash) ? !polymorphic_config.empty? : !!polymorphic_config
          is_polymorphic_subtype = !is_polymorphic &&
            value.class != rule.attribute_type &&
            value.class < rule.attribute_type

          actual_class = resolve_polymorphic_class(rule, value, is_polymorphic,
                                                   is_polymorphic_subtype)

          # Get transformation for the actual class
          child_transformation = if is_polymorphic || is_polymorphic_subtype
                                   actual_class.transformation_for(:xml,
                                                                   register)
                                 else
                                   rule.child_transformation || actual_class.transformation_for(
                                     :xml, register
                                   )
                                 end

          if child_transformation
            create_transformed_nested_element(rule, value, options,
                                              child_transformation)
          else
            create_fallback_nested_element(rule, value, options)
          end
        end

        # Resolve polymorphic class for value
        #
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param is_polymorphic [Boolean] Whether polymorphic config exists
        # @param is_polymorphic_subtype [Boolean] Whether value is a subtype
        # @return [Class] The actual class to use
        def resolve_polymorphic_class(rule, value, is_polymorphic,
is_polymorphic_subtype)
          polymorphic_config = rule.options[:polymorphic]

          if is_polymorphic
            if polymorphic_config.is_a?(Hash)
              poly_attr = polymorphic_config[:attribute]
              poly_class_map = polymorphic_config[:class_map]
              poly_value = value.send(poly_attr) if poly_attr && value.respond_to?(poly_attr)
              if poly_value && poly_class_map && (klass_name = poly_class_map[poly_value.to_s])
                Object.const_get(klass_name)
              else
                value.class
              end
            else
              value.class
            end
          elsif is_polymorphic_subtype
            value.class
          else
            rule.attribute_type
          end
        end

        # Create transformed nested element using child transformation
        #
        # @param rule [CompiledRule] The rule
        # @param value [Object] The model instance
        # @param options [Hash] Options
        # @param child_transformation [Transformation] The child transformation
        # @return [::Lutaml::Xml::DataModel::XmlElement] The created element
        def create_transformed_nested_element(rule, value, options,
child_transformation)
          parent_ns_class = options[:parent_namespace_class]
          parent_element_form_default = options[:parent_element_form_default]
          parent_uses_default_ns = parent_ns_class && parent_element_form_default == :qualified
          child_options = options.merge(parent_uses_default_ns: parent_uses_default_ns)

          child_element = child_transformation.transform(value, child_options)

          # Use parent's mapping name, not child's root name
          if rule.serialized_name != child_element.name
            child_element.instance_variable_set(:@name, rule.serialized_name)
          end

          child_element
        end

        # Create fallback nested element when no transformation available
        #
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options
        # @return [::Lutaml::Xml::DataModel::XmlElement] The created element
        def create_fallback_nested_element(rule, value, options)
          element_namespace_class = determine_element_namespace(
            rule,
            options[:parent_namespace_class],
            options[:parent_element_form_default],
          )

          element = ::Lutaml::Xml::DataModel::XmlElement.new(
            rule.serialized_name,
            element_namespace_class,
          )

          element.form = rule.form if rule.form
          text = serialize_value(value, rule, rule.attribute_type, nil)
          element.text_content = text if text
          element
        end

        # Create element for simple value (not a nested model)
        #
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @return [::Lutaml::Xml::DataModel::XmlElement] The created element
        def create_simple_value_element(rule, value, options, model_class,
register_id)
          element_namespace_class = determine_element_namespace(
            rule,
            options[:parent_namespace_class],
            options[:parent_element_form_default],
          )

          element = ::Lutaml::Xml::DataModel::XmlElement.new(
            rule.serialized_name,
            element_namespace_class,
          )

          element.form = rule.form if rule.form

          # Handle Hash type - expand hash into child elements
          if value.is_a?(::Hash) && rule.attribute_type == Lutaml::Model::Type::Hash
            add_hash_children(element, value)
            return element
          end

          text = serialize_value(value, rule, model_class, register_id)

          # Mark element as nil for xsi:nil rendering
          apply_nil_marker(element, value, rule)

          # Return element without text content for nil or empty strings
          return element if text.nil? || text.to_s.empty?

          apply_element_content(element, text, rule)

          element
        end

        # Add hash key-value pairs as child elements
        #
        # @param element [XmlElement] The parent element
        # @param hash [Hash] The hash value
        def add_hash_children(element, hash)
          hash.each do |key, val|
            child = ::Lutaml::Xml::DataModel::XmlElement.new(key.to_s)
            child.text_content = val.to_s
            element.add_child(child)
          end
        end

        # Apply nil marker to element if needed
        #
        # @param element [XmlElement] The element
        # @param value [Object] The value
        # @param rule [CompiledRule] The rule
        def apply_nil_marker(element, value, rule)
          if value.nil?
            apply_nil_marker_for_nil(element, rule)
          elsif Lutaml::Model::Utils.uninitialized?(value)
            apply_nil_marker_for_uninitialized(element, rule)
          elsif Lutaml::Model::Utils.empty?(value)
            apply_nil_marker_for_empty(element, rule)
          end
        end

        # Apply nil marker for nil value
        def apply_nil_marker_for_nil(element, rule)
          render_nil = rule.option(:render_nil)
          render_empty = rule.option(:render_empty)
          value_map = rule.option(:value_map) || {}
          to_map = value_map[:to] || value_map

          if render_nil == :as_nil || render_empty == :as_nil || to_map[:nil] == :nil
            element.instance_variable_set(:@is_nil, true)
          end
        end

        # Apply nil marker for uninitialized value
        def apply_nil_marker_for_uninitialized(element, rule)
          value_map = rule.option(:value_map) || {}
          to_map = value_map[:to] || value_map
          if to_map[:omitted] == :nil
            element.instance_variable_set(:@is_nil, true)
          end
        end

        # Apply nil marker for empty value
        def apply_nil_marker_for_empty(element, rule)
          value_map = rule.option(:value_map) || {}
          to_map = value_map[:to] || value_map
          if to_map[:empty] == :nil
            element.instance_variable_set(:@is_nil, true)
          end
        end

        # Apply content to element (text or raw)
        #
        # @param element [XmlElement] The element
        # @param text [String] The text content
        # @param rule [CompiledRule] The rule
        def apply_element_content(element, text, rule)
          if rule.raw
            # Store as raw content for adapter serialization
            element.instance_variable_set(:@raw_content, text.to_s)
          else
            # Normal text content - will be escaped by adapter
            element.text_content = text
          end

          # Apply cdata flag if set on the rule
          element.cdata = rule.cdata if rule.cdata
        end
      end
    end
  end
end
