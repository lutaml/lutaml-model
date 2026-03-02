# frozen_string_literal: true

module Lutaml
  module Xml
    module TransformationSupport
      # Module for applying transformation rules to create XML elements.
      #
      # Dispatches rule application to specific handlers based on mapping type:
      # - Element rules -> apply_element_rule
      # - Attribute rules -> apply_attribute_rule
      # - Content rules -> apply_content_rule
      # - Raw rules -> apply_raw_rule
      module RuleApplier
        include SkipLogic
        include ElementBuilder

        # Apply a single transformation rule
        #
        # @param parent [::Lutaml::Xml::DataModel::XmlElement] Parent element
        # @param rule [CompiledRule] The rule to apply
        # @param model_instance [Object] The model instance
        # @param options [Hash] Transformation options
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @param register [Register, nil] The register
        def apply_rule(parent, rule, model_instance, options, model_class,
register_id, register)
          # Skip pseudo-rules like root_namespace
          return if rule.option(:mapping_type) == :root_namespace

          # Check if this is a custom-method-only rule
          is_custom_method_only = custom_method_only?(rule)

          # Get attribute value - handle delegation and custom methods
          value = extract_rule_value(rule, model_instance,
                                     is_custom_method_only)

          # Handle render options and value_map
          should_skip = if is_custom_method_only
                          false
                        elsif rule.option(:delegate_from)
                          delegate_obj = model_instance.public_send(rule.option(:delegate_from))
                          should_skip_delegated_value?(value, rule,
                                                       delegate_obj)
                        else
                          should_skip_value?(value, rule, model_instance)
                        end
          return if should_skip

          # Apply export transformation if present BEFORE any other processing
          value = rule.transform_value(value, :export) if rule.value_transformer

          # Handle based on rule type
          case rule.option(:mapping_type)
          when :element
            apply_element_rule(parent, rule, value, options, model_class,
                               register_id, register)
          when :attribute
            apply_attribute_rule(parent, rule, value, options, model_class,
                                 register_id)
          when :content
            apply_content_rule(parent, rule, value, options, model_class,
                               register_id)
          when :raw
            apply_raw_rule(parent, rule, value)
          end
        end

        # Apply an element rule
        #
        # @param parent [::Lutaml::Xml::DataModel::XmlElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @param register [Register, nil] The register
        def apply_element_rule(parent, rule, value, options, model_class,
register_id, register)
          # Handle custom serialization methods
          if rule.has_custom_methods? && rule.custom_methods[:to]
            apply_custom_method(parent, rule, model_class,
                                options[:current_model])
            return
          end

          # Extract parent's namespace info for element_form_default inheritance
          parent_ns_class = parent.namespace_class
          parent_element_form_default = parent_ns_class&.element_form_default

          # Performance: Only create new options hash if values differ
          # This avoids allocations for unchanged namespace inheritance
          if options[:parent_namespace_class] == parent_ns_class &&
             options[:parent_element_form_default] == parent_element_form_default
            child_options = options
          else
            child_options = options.dup
            child_options[:parent_namespace_class] = parent_ns_class
            child_options[:parent_element_form_default] = parent_element_form_default
          end

          apply_element_value(parent, rule, value, child_options, model_class,
                              register_id, register)
        end

        # Apply an attribute rule
        #
        # @param parent [::Lutaml::Xml::DataModel::XmlElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        def apply_attribute_rule(parent, rule, value, options, model_class,
register_id)
          # Handle custom serialization methods
          if rule.has_custom_methods? && rule.custom_methods[:to]
            apply_custom_method(parent, rule, model_class,
                                options[:current_model])
            return
          end

          text = serialize_value(value, rule, model_class, register_id)
          return unless text

          # Determine attribute namespace - type namespace takes precedence
          attr_namespace_class = if rule.attribute_type.respond_to?(:xml_namespace) &&
              rule.attribute_type.xml_namespace
                                   rule.attribute_type.xml_namespace
                                 else
                                   rule.namespace_class
                                 end

          attr = ::Lutaml::Xml::DataModel::XmlAttribute.new(
            rule.serialized_name,
            text,
            attr_namespace_class,
          )

          parent.add_attribute(attr)
        end

        # Apply a content mapping rule (map_content directive)
        #
        # For mixed content, when value is an Array, each item is added as a
        # separate child text node. For regular content, value is set as text_content.
        #
        # @param parent [::Lutaml::Xml::DataModel::XmlElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        def apply_content_rule(parent, rule, value, options, model_class,
register_id)
          # Handle custom serialization methods
          if rule.has_custom_methods? && rule.custom_methods[:to]
            apply_custom_method(parent, rule, model_class,
                                options[:current_model])
            return
          end

          return if value.nil?
          return if Lutaml::Model::Utils.uninitialized?(value)

          xml_mapping = model_class.mappings_for(:xml)
          is_mixed = rule.mixed_content || xml_mapping&.mixed_content? || value.is_a?(Array)

          if value.is_a?(Array) && is_mixed
            apply_mixed_content(parent, value)
          else
            # For regular content, serialize value and set as text_content
            text = serialize_value(value, rule, model_class, register_id)
            parent.text_content = text if text
          end

          parent.cdata = rule.cdata if rule.cdata
        end

        # Apply a raw mapping rule (map_all directive)
        #
        # Raw content is the entire inner XML as a string, including elements and text.
        # Store it on the parent element so adapters can serialize it as raw XML fragment.
        #
        # @param parent [::Lutaml::Xml::DataModel::XmlElement] Parent element
        # @param rule [CompiledRule] The rule (unused but kept for API consistency)
        # @param value [Object] The raw XML content as string
        def apply_raw_rule(parent, _rule, value)
          return unless value
          return if value.to_s.empty?

          parent.instance_variable_set(:@raw_content, value.to_s)
        end

        private

        # Check if rule is custom-method-only (no real attribute)
        #
        # @param rule [CompiledRule] The rule
        # @return [Boolean] true if custom method only
        def custom_method_only?(rule)
          # Check if attribute name is a placeholder (e.g., :__content__)
          return true if rule.attribute_name.to_s.start_with?("__") &&
            rule.attribute_name.to_s.end_with?("__")

          # Also check if rule has custom methods but attribute_type is nil
          # This handles cases where we inferred an attribute name for custom methods
          rule.has_custom_methods? && rule.attribute_type.nil?
        end

        # Extract value for a rule
        #
        # @param rule [CompiledRule] The rule
        # @param model_instance [Object] The model instance
        # @param is_custom_method_only [Boolean] Whether it's custom method only
        # @return [Object, nil] The extracted value
        def extract_rule_value(rule, model_instance, is_custom_method_only)
          if is_custom_method_only
            nil
          elsif rule.option(:delegate_from)
            delegate_obj = model_instance.public_send(rule.option(:delegate_from))
            delegate_obj&.public_send(rule.attribute_name)
          else
            model_instance.public_send(rule.attribute_name)
          end
        end

        # Apply custom method using wrapper
        #
        # @param parent [XmlElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param model_class [Class] The model class
        # @param model_instance [Object] The model instance
        def apply_custom_method(parent, rule, model_class, model_instance)
          wrapper = CustomMethodWrapper.new(parent, rule)
          mapper_instance = model_class.new
          mapper_instance.send(rule.custom_methods[:to], model_instance,
                               parent, wrapper)
        end

        # Apply element value handling collections
        #
        # @param parent [XmlElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @param register [Register, nil] The register
        def apply_element_value(parent, rule, value, options, model_class,
register_id, register)
          if rule.collection?
            apply_collection_element(parent, rule, value, options, model_class,
                                     register_id, register)
          elsif value.is_a?(Array)
            # Handle single value where value is Array (backward compatibility)
            value.each do |item|
              element = create_element_for_value(rule, item, options,
                                                 model_class, register_id, register)
              parent.add_child(element) if element
            end
          else
            element = create_element_for_value(rule, value, options,
                                               model_class, register_id, register)
            parent.add_child(element) if element
          end
        end

        # Apply collection element with nil/empty handling
        #
        # @param parent [XmlElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @param register [Register, nil] The register
        def apply_collection_element(parent, rule, value, options, model_class,
register_id, register)
          if value.nil?
            apply_nil_collection(parent, rule, options, model_class,
                                 register_id, register)
          elsif Lutaml::Model::Utils.empty?(value)
            apply_empty_collection(parent, rule, options, model_class,
                                   register_id, register)
          else
            Array(value).each do |item|
              element = create_element_for_value(rule, item, options,
                                                 model_class, register_id, register)
              parent.add_child(element) if element
            end
          end
        end

        # Apply nil collection based on render_nil option
        def apply_nil_collection(parent, rule, options, model_class,
register_id, register)
          render_nil = rule.option(:render_nil)
          if render_nil == :as_nil
            element = create_element_for_value(rule, nil, options, model_class,
                                               register_id, register)
            parent.add_child(element) if element
          elsif render_nil == :as_blank
            element = create_element_for_value(rule, "", options, model_class,
                                               register_id, register)
            parent.add_child(element) if element
          else
            Array(nil).each do |item|
              element = create_element_for_value(rule, item, options,
                                                 model_class, register_id, register)
              parent.add_child(element) if element
            end
          end
        end

        # Apply empty collection based on render_empty option
        def apply_empty_collection(parent, rule, options, model_class,
register_id, register)
          render_empty = rule.option(:render_empty)
          if render_empty == :as_nil
            element = create_element_for_value(rule, nil, options, model_class,
                                               register_id, register)
            parent.add_child(element) if element
          elsif render_empty == :as_blank
            element = create_element_for_value(rule, "", options, model_class,
                                               register_id, register)
            parent.add_child(element) if element
          end
          # For true, :as_empty, or unset: skip empty collections
        end

        # Apply mixed content interleaving
        #
        # @param parent [XmlElement] Parent element
        # @param value [Array] The content array
        def apply_mixed_content(parent, value)
          # Get existing element children (added by element rules before this content rule)
          existing_children = parent.children.dup

          # Clear children and rebuild with interleaved content
          parent.children.clear

          # Add content[0] before first element (if exists)
          parent.add_child(value[0].to_s) if value[0]

          # Interleave remaining content with existing elements
          existing_children.each_with_index do |child, index|
            parent.add_child(child)

            # Add content after this element (if exists)
            content_index = index + 1
            parent.add_child(value[content_index].to_s) if value[content_index]
          end
        end
      end
    end
  end
end
