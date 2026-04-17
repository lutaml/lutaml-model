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
          # Only treat as nested model when the attribute type is a Serializable
          # class AND the value is not a nil/empty marker from collection handlers.
          # Nil and empty string markers should create simple elements, not attempt
          # nested model transformation.
          is_nested_model = rule.attribute_type.is_a?(Class) &&
            rule.attribute_type < Lutaml::Model::Serialize &&
            !value.nil? &&
            !(value.is_a?(String) && value.empty?)

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
        #      - BUT: if parent has element_form_default :unqualified AND
        #        the namespace is the same as parent's, override to blank
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
          # BUT: if parent has element_form_default :unqualified AND
          # the namespace is the same as parent's, override to blank namespace
          # W3C: elementFormDefault only applies to locally declared elements
          # in the same namespace. Elements from other namespaces are always qualified.
          if rule.namespace_class
            if parent_element_form_default == :unqualified &&
                rule.namespace_class == parent_namespace_class
              # Parent schema says unqualified, and this is the same namespace
              # Override to blank namespace (nil)
              nil
            else
              rule.namespace_class
            end
          elsif rule.form == :unqualified
            # Priority 3: Form override unqualified
            nil
          elsif parent_element_form_default == :qualified && parent_namespace_class
            # Priority 4: Inherit parent's namespace (element_form_default: :qualified)
            # BUT: W3C elementFormDefault only applies to locally declared elements.
            # Children WITHOUT their own namespace declaration should NOT inherit parent's ns.
            # Only inherit if the child model explicitly declares a namespace.
            attr_type = rule.attribute_type
            if attr_type.is_a?(Class) && attr_type.include?(Lutaml::Model::Serialize)
              attr_mapping = attr_type.mappings_for(:xml)
              attr_ns = attr_mapping&.namespace_class
              attr_ns_param = attr_mapping&.send(:namespace_param)
              # Use child's explicit namespace if it differs from parent's
              # If child has no namespace declaration (nil) or explicit blank (:blank),
              # do NOT inherit parent's namespace - return nil
              if attr_ns && attr_ns != parent_namespace_class
                attr_ns
              elsif attr_ns_param.nil? && attr_ns.nil?
                # Child has NO namespace declaration at all - do not apply element_form_default
                nil
              else
                parent_namespace_class
              end
            else
              parent_namespace_class
            end
          elsif rule.form == :qualified && parent_namespace_class
            # Priority 5: Form override qualified
            parent_namespace_class
          end
        end

        private

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
          child_options = options.merge(
            parent_uses_default_ns: parent_uses_default_ns,
            parent_namespace_class: parent_ns_class,
          )

          # For doubly-defined namespace support: propagate namespace prefix to child model instance.
          # Check @__xml_ns_prefixes (populated during deserialization for ALL attributes).
          # If @__xml_ns_prefixes has the prefix, propagate to the child model.
          # Only set @__xml_namespace_prefix when:
          # 1. Parent has NO namespace class (doubly-defined case): set so NamespaceCollector reads it
          # 2. Parent HAS namespace class AND child has same namespace (same URI): set
          #    so NamespaceCollector reads it (will be cleared below for mixed content)
          # Do NOT set when:
          # - Parent has namespace class AND child has different namespace (mixed content
          #   with different URIs) -> child has its own ns, use child's prefix_default
          # - Child's namespace is self-declared through its attribute TYPE (different from parent)
          #   -> child's XmlElement gets its own ns, use child's prefix_default
          child_ns_class = if value.class.respond_to?(:mappings_for)
                             value.class.mappings_for(:xml)&.namespace_class
                           end
          ns_prefix = nil
          parent_model = options[:current_model]
          if parent_model.is_a?(::Lutaml::Model::Serialize)
            prefixes = parent_model.instance_variable_get(:@__xml_ns_prefixes)
            ns_prefix = prefixes[rule.attribute_name] if prefixes
          end
          child_self_declared_ns = child_ns_class &&
            parent_ns_class &&
            child_ns_class != parent_ns_class
          # ns_prefix_valid: check if ns_prefix from @__xml_ns_prefixes actually matches
          # what the child's namespace class expects. This prevents stale prefixes from
          # deserialization (e.g., parent's dcterms prefix) from being applied to children
          # that don't expect that prefix.
          ns_prefix_valid = if ns_prefix && !ns_prefix.empty? && child_ns_class
                              child_ns_class.prefix_default == ns_prefix ||
                                namespace_prefix_valid_for_class(ns_prefix,
                                                                 child_ns_class)
                            else
                              false
                            end
          # Dual-namespace case: when child has a different namespace URI than parent,
          # only use ns_prefix if it actually matches the child's expected prefix.
          # This preserves the dual-namespace behavior (w:rPr inside m:r) while preventing
          # stale prefixes (dcterms prefix leaking to children that should use default ns).
          dual_namespace_applies = child_self_declared_ns && ns_prefix_valid
          # Parent has no ns OR child shares parent's URI (and child doesn't self-declare ns)
          # OR dual-namespace case where child's ns_prefix matches its namespace expectation
          if (parent_ns_class.nil? || (child_ns_class && child_ns_class.uri == parent_ns_class.uri) ||
              dual_namespace_applies) &&
              !child_self_declared_ns && ns_prefix && !ns_prefix.empty?
            value.instance_variable_set(:@__xml_namespace_prefix, ns_prefix)
          end
          # For dual-namespace case: set @__xml_namespace_prefix on model so it can be
          # transferred to XmlElement at lines 282-289 for prefix preservation.
          if dual_namespace_applies && ns_prefix && !ns_prefix.empty?
            value.instance_variable_set(:@__xml_namespace_prefix, ns_prefix)
          end

          # Also set @__xml_namespace_prefix on the XmlElement for doubly-defined case.
          # This is read by NamespaceCollector to set NamespaceUsage.used_prefix.
          # For doubly-defined: parent has no ns, child's ns_prefix is from @__xml_ns_prefixes
          # (not from parent's @__xml_namespace_prefix).
          # For mixed content: parent's XmlElement already has @__xml_namespace_prefix set.
          if parent_ns_class.nil? && ns_prefix && !ns_prefix.empty? && !child_ns_class
            # Doubly-defined case: parent has no ns, child has ns class.
            # Set on XmlElement so NamespaceCollector reads it.
            # The value will be set on the model instance above (via @__xml_namespace_prefix)
            # and we'll set it on XmlElement too so collection phase picks it up.
          end

          child_element = child_transformation.transform(value, child_options)

          # Dual-namespace support: when the child model was deserialized from an element
          # with a different namespace than the parent (e.g., w:rPr child of m:r),
          # transfer the model's @__xml_namespace_prefix to the child XmlElement so the
          # NamespaceCollector and DeclarationPlanner can use the correct prefix.
          # The transformation.rb only sets this when parent and child share a namespace,
          # but for dual-namespace elements we need the child's prefix preserved.
          if child_ns_class && parent_ns_class &&
              child_ns_class != parent_ns_class &&
              child_element.instance_variable_get(:@__xml_namespace_prefix).nil?
            model_prefix = value.instance_variable_get(:@__xml_namespace_prefix)
            if model_prefix && !model_prefix.empty?
              child_element.instance_variable_set(:@__xml_namespace_prefix,
                                                  model_prefix)
            end
          end

          # For mixed content support: clear @__xml_namespace_prefix on child XmlElement
          # when the parent XmlElement has an explicit namespace prefix.
          # This ensures:
          # - Doubly-defined: parent's XmlElement has no @__xml_namespace_prefix -> DON'T clear
          #   (preserve the XmlElement's prefix for NamespaceCollector to read)
          # - Mixed content (parent XmlElement has explicit prefix): CLEAR
          #   (child should use its own namespace's default prefix, not parent's deserialization prefix)
          # CRITICAL: Only clear when child's namespace URI matches parent's namespace URI.
          # For dual-namespace (different URIs), the child's prefix was set from input XML
          # and must be preserved for round-trip fidelity.
          parent_element = options[:parent_element]
          parent_has_prefix = parent_element &&
            !parent_element.instance_variable_get(:@__xml_namespace_prefix).to_s.empty?
          if parent_ns_class && child_ns_class && parent_has_prefix &&
              child_ns_class.uri == parent_ns_class.uri &&
              child_element.instance_variable_get(:@__xml_namespace_prefix)
            child_element.instance_variable_set(:@__xml_namespace_prefix, nil)
          end

          # Use parent's mapping name, not child's root name
          if rule.serialized_name != child_element.name
            child_element.instance_variable_set(:@name, rule.serialized_name)
          end

          # W3C elementFormDefault: unqualified override
          # When parent's namespace has element_form_default :unqualified and the child's
          # namespace is the same as the parent's, override to blank namespace.
          # This ensures local elements are not namespace-qualified per W3C spec.
          if parent_element_form_default == :unqualified &&
              parent_ns_class &&
              child_element.namespace_class == parent_ns_class
            child_element.instance_variable_set(:@namespace_class, nil)
          end

          child_element
        end

        # Check if a prefix is valid for a namespace class by verifying it maps to the same URI.
        # This ensures we only use ns_prefix from @__xml_ns_prefixes when it actually matches
        # the child's expected namespace prefix.
        #
        # @param prefix [String, nil] The prefix to check
        # @param ns_class [Class] The namespace class
        # @return [Boolean] True if prefix is valid for this namespace class
        def namespace_prefix_valid_for_class(prefix, ns_class)
          return false unless prefix && ns_class

          ns_class.prefix_default == prefix
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

          # Transfer @__xml_namespace_prefix from model to element for round-trip support.
          # This ensures the original prefix from deserialization is preserved during
          # serialization, even when using fallback element creation.
          if value.is_a?(::Lutaml::Model::Serialize)
            model_ns_prefix = value.instance_variable_get(:@__xml_namespace_prefix)
            element.instance_variable_set(:@__xml_namespace_prefix,
                                          model_ns_prefix)
          end

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
          # Compute namespace info upfront for use in ns_prefix lookup.
          # We need same_uri BEFORE checking @__xml_ns_prefixes fallback.
          parent_ns_class = options[:parent_namespace_class]
          rule_ns_class = rule.namespace_class

          rule_expected_ns_class = if rule_ns_class
                                     rule_ns_class
                                   elsif rule.attribute_type.is_a?(Class) && rule.attribute_type.include?(::Lutaml::Model::Serialize)
                                     rule.attribute_type.mappings_for(:xml)&.namespace_class
                                   elsif rule.attribute_type.is_a?(Class) && rule.attribute_type <= ::Lutaml::Model::Type::Value
                                     rule.attribute_type.namespace_class
                                   end

          parent_uri = parent_ns_class&.uri
          rule_expected_uri = rule_expected_ns_class&.uri
          same_uri = parent_uri && rule_expected_uri && parent_uri == rule_expected_uri

          # Determine if the child has its own explicit namespace declaration (different URI
          # from parent). Used to decide whether to propagate parent's namespace prefix.
          # Key distinction: same namespace URI with different prefix (doubly-defined) is NOT
          # an explicit declaration - it's a prefix variant that should use parent's prefix.
          child_attr_type_has_explicit_ns = if rule_ns_class
                                              false
                                            elsif rule.attribute_type.is_a?(Class) && rule.attribute_type.include?(::Lutaml::Model::Serialize)
                                              child_mapping_ns = rule.attribute_type.mappings_for(:xml)&.namespace_class
                                              child_mapping_ns && child_mapping_ns.uri != parent_uri
                                            elsif rule.attribute_type.is_a?(Class) && rule.attribute_type <= ::Lutaml::Model::Type::Value
                                              rule.attribute_type.namespace_class && rule.attribute_type.namespace_class.uri != parent_uri
                                            else
                                              false
                                            end

          # Look up namespace prefix from parent model's @__xml_ns_prefixes.
          # For doubly-defined namespace support: preserve original prefix from deserialization.
          parent_model = options[:current_model]
          ns_prefix = nil
          if options[:use_prefix] != false && parent_model.is_a?(::Lutaml::Model::Serialize)
            prefixes = parent_model.instance_variable_get(:@__xml_ns_prefixes)

            # Only use @__xml_ns_prefixes lookup when the child's XmlElement was explicit.
            # If prefixes.key?(attr.name) is false, the child's XmlElement was not explicit
            # (inherited namespace), so @__xml_ns_prefixes was not set and we should NOT
            # use the fallback to parent's @__xml_namespace_prefix.
            if prefixes&.key?(rule.attribute_name)
              ns_prefix = prefixes[rule.attribute_name]
            end

            # Fallback for nested Serializable models: @__xml_ns_prefixes is only set for
            # non-Serializable attribute types. For Serializable types (e.g., nested model
            # elements), we fall back to the parent's @__xml_namespace_prefix when the parent's
            # namespace URI matches the child's expected URI. This ensures prefix propagation
            # for nested models that share the parent's namespace.
            # Only use this fallback when @__xml_ns_prefixes was set (child's XmlElement was explicit).
            if ns_prefix.nil? && same_uri && prefixes&.key?(rule.attribute_name)
              parent_prefix = parent_model.instance_variable_get(:@__xml_namespace_prefix)
              ns_prefix = parent_prefix if parent_prefix && !parent_prefix.empty?
            end

            # Dual-namespace fallback: when the child model has a different namespace from
            # the parent (same_uri is false), check the child model instance's own
            # @__xml_namespace_prefix. This handles the case where a child Serializable was
            # deserialized from a differently-namespaced element (e.g., w:rPr child of m:r).
            if ns_prefix.nil? && value.is_a?(::Lutaml::Model::Serialize)
              child_own_prefix = value.instance_variable_get(:@__xml_namespace_prefix)
              ns_prefix = child_own_prefix if child_own_prefix && !child_own_prefix.empty?
            end
          end

          # For doubly-defined namespace support: use parent's ns_class when there's an
          # explicit prefix from @__xml_ns_prefixes AND the rule has no explicit namespace.
          # Handle two cases:
          # 1. same_uri=true: use parent's ns_class (same namespace, preserves prefix)
          # 2. rule_expected_ns_class=nil AND prefix set AND child has no explicit ns: use parent's ns_class
          #    (element has no explicit ns declaration, prefix was set during parsing)
          # IMPORTANT: Use rule_expected_ns_class (includes attribute type's namespace) instead of
          # rule_ns_class (only the mapping rule's direct namespace). This prevents incorrectly
          # propagating parent's prefix to children whose attribute TYPE declares a namespace.
          #
          # CRITICAL: If child's namespace is self-declared (child's namespace class differs from
          # parent's namespace class), DON'T use parent's @__xml_ns_prefixes. The child has its
          # own namespace declaration and should use its namespace's default prefix.
          use_parent_ns = nil
          if ns_prefix && !ns_prefix.empty? && !rule_ns_class && parent_ns_class
            child_self_declared_ns = rule_expected_ns_class &&
              rule_expected_ns_class != parent_ns_class
            if rule_expected_ns_class.nil? && !child_attr_type_has_explicit_ns && !child_self_declared_ns
              use_parent_ns = parent_ns_class
            end
          end

          effective_ns_class = if use_parent_ns
                                 parent_ns_class
                               else
                                 determine_element_namespace(
                                   rule,
                                   options[:parent_namespace_class],
                                   options[:parent_element_form_default],
                                 )
                               end

          element = ::Lutaml::Xml::DataModel::XmlElement.new(
            rule.serialized_name,
            effective_ns_class,
          )

          # Only preserve the deserialization prefix when:
          # 1. ns_prefix is set (from @__xml_ns_prefixes lookup or parent fallback)
          # 2. The element has no explicit namespace in its rule AND no explicit namespace
          #    in its attribute TYPE (child_attr_type_has_explicit_ns is false)
          # 3. The child's namespace is NOT self-declared (child's ns != parent's ns)
          #    -> if child has its own namespace, use that, not the parent's prefix
          child_self_declared_ns = rule_expected_ns_class &&
            rule_expected_ns_class != parent_ns_class
          if ns_prefix && !ns_prefix.empty? && !child_self_declared_ns &&
              !child_attr_type_has_explicit_ns
            element.instance_variable_set(:@__xml_namespace_prefix, ns_prefix)
          end

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
          to_map = (rule.option(:value_map) || {})[:to] || {}

          if to_map[:nil] == :nil
            element.xsi_nil = true
          end
        end

        # Apply nil marker for uninitialized value
        def apply_nil_marker_for_uninitialized(element, rule)
          to_map = (rule.option(:value_map) || {})[:to] || {}
          if to_map[:omitted] == :nil
            element.xsi_nil = true
          end
        end

        # Apply nil marker for empty scalar value
        def apply_nil_marker_for_empty(element, rule)
          to_map = (rule.option(:value_map) || {})[:to] || {}
          if to_map[:empty] == :nil
            element.xsi_nil = true
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
            element.raw_content = text.to_s
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
