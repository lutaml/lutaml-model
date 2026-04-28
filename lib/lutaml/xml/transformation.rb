# frozen_string_literal: true

module Lutaml
  module Xml
    # XML-specific transformation implementation.
    #
    # Transforms model instances into XmlElement trees without
    # triggering type resolution or imports during transformation.
    #
    # This class orchestrates the transformation process by including
    # specialized modules for each concern:
    # - TransformationSupport::RuleCompiler: Compiles mapping DSL to CompiledRule objects
    # - TransformationSupport::SkipLogic: Determines if values should be skipped
    # - TransformationSupport::ValueSerializer: Serializes values to XML strings
    # - TransformationSupport::ElementBuilder: Creates XML elements from values
    # - TransformationSupport::OrderedApplier: Applies rules in element order for round-trip
    # - TransformationSupport::RuleApplier: Dispatches rule application to handlers
    class Transformation < Lutaml::Model::Transformation
      include TransformationSupport::RuleCompiler
      include TransformationSupport::RuleApplier
      include TransformationSupport::OrderedApplier

      # Transform a model instance into XmlElement tree
      #
      # @param model_instance [Object] The model instance to transform
      # @param options [Hash] Transformation options
      # @return [::Lutaml::Xml::DataModel::XmlElement] The root XML element
      def transform(model_instance, options = {})
        # Get root element name from mapping
        mapping = model_class.mappings_for(:xml, register_id)
        root_name = options[:tag_name] ||
          mapping.root_element ||
          (model_class.name&.split("::")&.last || "anonymous")

        # Get root namespace
        root_namespace = mapping.namespace_class

        # Check if this root element needs xmlns="" due to parent context
        parent_uses_default_ns = options[:parent_uses_default_ns]
        child_explicitly_blank = mapping.namespace_param == :blank
        needs_xmlns_blank = parent_uses_default_ns && child_explicitly_blank

        # Create root element
        root = ::Lutaml::Xml::DataModel::XmlElement.new(root_name,
                                                        root_namespace)

        # Preserve original namespace prefix for doubly-defined namespace support.
        # The model instance carries @__xml_namespace_prefix from deserialization.
        # ONLY set on root XmlElement when:
        # (a) This is the root of the to_xml call (no parent) OR
        # (b) The child's namespace matches the parent's namespace (same namespace).
        # DO NOT set when child's namespace differs from parent's - the FormatPreservationRule
        # will correctly determine the format based on input_prefix_formats.
        if model_instance.is_a?(::Lutaml::Model::Serialize)
          ns_prefix = model_instance.xml_namespace_prefix
          if ns_prefix && !ns_prefix.empty?
            # Only set if root of to_xml call OR namespaces match
            parent_ns_class = options[:parent_namespace_class]
            if parent_ns_class.nil? || parent_ns_class == root_namespace
              root.xml_namespace_prefix = ns_prefix
            end
          end

          # Preserve original namespace URI for namespace alias support.
          # When the model's namespace URI differs from the canonical URI (it's an alias),
          # transfer this information to the XmlElement so it can be used during
          # serialization for round-trip fidelity.
          original_ns_uri = model_instance.original_namespace_uri
          if original_ns_uri && !original_ns_uri.empty?
            root.original_namespace_uri = original_ns_uri
          end
        end

        # Mark that this element needs xmlns="" (for DeclarationPlanner)
        if needs_xmlns_blank
          root.needs_xmlns_blank = true
        end

        # Store namespace_scope_config for hoisting support
        namespace_scope_config = mapping.namespace_scope_config || []
        root.namespace_scope_config = namespace_scope_config

        # Handle schema_location if present
        handle_schema_location(root, model_instance)

        # Handle xml:space="preserve" for mixed content elements
        handle_xml_space(root, mapping)

        # Handle processing instruction mappings
        apply_processing_instruction_mappings(root, model_instance, mapping)

        # Determine serialization mode
        use_element_order = should_use_element_order?(model_instance, mapping)

        if use_element_order
          apply_ordered_rules(root, model_instance, options)
        else
          apply_standard_rules(root, model_instance, options)
        end

        root
      end

      # Collect all namespaces used in this transformation
      #
      # @return [Array<Class>] Array of XmlNamespace classes
      def all_namespaces
        namespaces = []
        compiled_rules.each do |rule|
          namespaces.concat(rule.all_namespaces)
        end
        namespaces.uniq
      end

      private

      # Get the register ID, handling both Symbol and Register objects
      #
      # @return [Symbol, nil] The register ID
      def register_id
        return @register if @register.is_a?(Symbol)

        @register_id
      end

      # Compile XML mapping DSL into pre-compiled rules
      #
      # Delegates to RuleCompiler module
      #
      # @param mapping_dsl [Xml::Mapping] The XML mapping to compile
      # @return [Array<CompiledRule>] Array of compiled transformation rules
      def compile_rules(mapping_dsl)
        super(mapping_dsl, model_class, register_id, register)
      end

      # Handle schema_location attribute
      #
      # @param root [XmlElement] Root element
      # @param model_instance [Object] The model instance
      def handle_schema_location(root, model_instance)
        # Case 1: SchemaLocation object (programmatic creation)
        if model_instance.respond_to?(:schema_location) && model_instance.schema_location
          schema_loc = model_instance.schema_location
          if schema_loc.respond_to?(:to_xml_attributes)
            schema_attrs = schema_loc.to_xml_attributes
            schema_attrs.each do |attr_name, attr_value|
              attr = ::Lutaml::Xml::DataModel::XmlAttribute.new(attr_name,
                                                                attr_value, nil)
              root.add_attribute(attr)
            end
          end
        # Case 2: @raw_schema_location string (from parsing/round-trip)
        elsif model_instance.respond_to?(:raw_schema_location) && model_instance.raw_schema_location
          raw_schema_loc = model_instance.raw_schema_location
          if raw_schema_loc && !raw_schema_loc.empty?
            add_raw_schema_location(root, raw_schema_loc)
          end
        end
      end

      # Add raw schema location attributes
      #
      # @param root [XmlElement] Root element
      # @param raw_schema_loc [String] The raw schema location
      def add_raw_schema_location(root, raw_schema_loc)
        xsi_ns_attr = ::Lutaml::Xml::DataModel::XmlAttribute.new(
          "xmlns:xsi",
          "http://www.w3.org/2001/XMLSchema-instance",
          nil,
        )
        root.add_attribute(xsi_ns_attr)

        schema_loc_attr = ::Lutaml::Xml::DataModel::XmlAttribute.new(
          "xsi:schemaLocation",
          raw_schema_loc,
          nil,
        )
        root.add_attribute(schema_loc_attr)
      end

      # Handle xml:space="preserve" for mixed content elements
      #
      # Mixed content elements are whitespace-sensitive by definition.
      # This method automatically adds xml:space="preserve" when serializing
      # mixed content, unless the user has explicitly set a value.
      #
      # @param root [XmlElement] Root element
      # @param model_instance [Object] The model instance
      # @param mapping [Xml::Mapping] The mapping
      def handle_xml_space(root, mapping)
        return unless mapping&.preserve_whitespace?

        # Don't add if user has defined a space attribute
        # (user controls xml:space themselves)
        space_rule = compiled_rules.find do |rule|
          rule.attribute_name == :space || rule.serialized_name == "space"
        end

        return if space_rule

        # Add xml:space="preserve" attribute
        space_attr = ::Lutaml::Xml::DataModel::XmlAttribute.new(
          "space",
          "preserve",
          ::Lutaml::Xml::W3c::XmlNamespace,
        )
        root.add_attribute(space_attr)
      end

      # Apply processing instruction mappings to the root element
      #
      # Reads PI mappings from the mapping DSL and generates PIs on the
      # root XmlElement from the model's attribute values.
      #
      # @param root [XmlElement] Root element
      # @param model_instance [Object] The model instance
      # @param mapping [Xml::Mapping] The mapping
      def apply_processing_instruction_mappings(root, model_instance, mapping)
        pi_mappings = mapping.processing_instruction_mappings
        return if pi_mappings.empty?

        pi_mappings.each do |pi_mapping|
          value = model_instance.public_send(pi_mapping.to)
          next if value.nil?

          if value.is_a?(Hash)
            value.each do |k, v|
              next if v.nil?

              root.add_processing_instruction(pi_mapping.target,
                                              "#{k}=\"#{v}\"")
            end
          elsif value.is_a?(Array)
            value.each do |content|
              root.add_processing_instruction(pi_mapping.target, content)
            end
          end
        end
      end

      # Check if element order should be used for serialization
      #
      # @param model_instance [Object] The model instance
      # @param mapping [Xml::Mapping] The mapping
      # @return [Boolean] true if element order should be used
      def should_use_element_order?(model_instance, mapping)
        has_element_order = model_instance.respond_to?(:element_order) &&
          model_instance.element_order &&
          !model_instance.element_order.empty?

        has_raw_mapping = mapping&.raw_mapping
        mapping_is_ordered = mapping&.ordered?

        has_element_order && !has_raw_mapping && mapping_is_ordered
      end

      # Apply rules using element order
      #
      # @param root [XmlElement] Root element
      # @param model_instance [Object] The model instance
      # @param options [Hash] Options
      def apply_ordered_rules(root, model_instance, options)
        apply_rules_in_order(
          root, model_instance, options,
          compiled_rules, model_class, register_id
        ) do |action, rule, value, set_xsi_nil|
          rule_options = options.merge(current_model: model_instance)
          case action
          when :apply_rule
            apply_rule(root, rule, model_instance, rule_options, model_class,
                       register_id, register)
          when :apply_single
            set_xsi_nil ||= false
            apply_element_rule_single(
              parent: root,
              rule: rule,
              value: value,
              options: rule_options,
            ) do |r, v, child_opts|
              element = create_element_for_value(r, v, child_opts, model_class,
                                                 register_id, register)
              element.xsi_nil = true if element && set_xsi_nil
              element
            end
          end
        end
      end

      # Apply rules in standard order
      #
      # @param root [XmlElement] Root element
      # @param model_instance [Object] The model instance
      # @param options [Hash] Options
      def apply_standard_rules(root, model_instance, options)
        compiled_rules.each do |rule|
          next unless valid_mapping?(rule, options)

          rule_options = options.merge(current_model: model_instance)
          apply_rule(root, rule, model_instance, rule_options, model_class,
                     register_id, register)
        end
      end

      # Serialize a value to string for XML output
      #
      # Delegates to ValueSerializer module
      #
      # @param value [Object] The value to serialize
      # @param rule [CompiledRule] The rule
      # @return [String, nil] Serialized value
      def serialize_value(value, rule, model_class = self.model_class,
register_id = self.register_id)
        super
      end

      # Create an element for a value
      #
      # Delegates to ElementBuilder module
      #
      # @param rule [CompiledRule] The rule
      # @param value [Object] The value
      # @param options [Hash] Options
      # @return [XmlElement, nil] The created element
      def create_element_for_value(rule, value, options,
model_class = self.model_class, register_id = self.register_id, register = self.register)
        super
      end

      # Build child transformation for nested model
      #
      # Delegates to RuleCompiler module
      #
      # @param type_class [Class] The nested model class
      # @return [Transformation, nil] Child transformation or nil
      def build_child_transformation(type_class, register = self.register)
        super
      end
    end
  end
end
