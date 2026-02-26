# frozen_string_literal: true

require_relative "../model/transformation"
require_relative "../model/compiled_rule"
require_relative "data_model"
require_relative "transformation/custom_method_wrapper"
require_relative "transformation/rule_compiler"
require_relative "transformation/skip_logic"
require_relative "transformation/value_serializer"
require_relative "transformation/element_builder"
require_relative "transformation/ordered_applier"
require_relative "transformation/rule_applier"

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

        # Mark that this element needs xmlns="" (for DeclarationPlanner)
        if needs_xmlns_blank
          root.instance_variable_set(:@needs_xmlns_blank,
                                     true)
        end

        # Store namespace_scope_config for hoisting support
        namespace_scope_config = mapping.namespace_scope_config || []
        root.instance_variable_set(:@namespace_scope_config,
                                   namespace_scope_config)

        # Handle schema_location if present
        handle_schema_location(root, model_instance)

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
        elsif model_instance.instance_variable_defined?(:@raw_schema_location)
          raw_schema_loc = model_instance.instance_variable_get(:@raw_schema_location)
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
        ) do |action, rule, value|
          rule_options = options.merge(current_model: model_instance)
          case action
          when :apply_rule
            apply_rule(root, rule, model_instance, rule_options, model_class,
                       register_id, register)
          when :apply_single
            apply_element_rule_single(
              parent: root,
              rule: rule,
              value: value,
              options: rule_options,
            ) do |r, v, child_opts|
              create_element_for_value(r, v, child_opts, model_class,
                                       register_id, register)
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
