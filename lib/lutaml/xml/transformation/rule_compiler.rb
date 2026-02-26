# frozen_string_literal: true

module Lutaml
  module Xml
    module TransformationSupport
      # Module for compiling XML mapping DSL into pre-compiled rules.
      #
      # Transforms mapping DSL definitions into CompiledRule objects that can
      # be used during serialization without triggering type resolution.
      module RuleCompiler
        # Compile XML mapping DSL into pre-compiled rules
        #
        # @param mapping_dsl [Xml::Mapping] The XML mapping to compile
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @param register [Register, nil] The register object
        # @return [Array<CompiledRule>] Array of compiled transformation rules
        def compile_rules(mapping_dsl, model_class, register_id, register)
          return [] unless mapping_dsl

          rules = []

          # Compile element mappings
          mapping_dsl.elements.each do |mapping_rule|
            rule = compile_element_rule(mapping_rule, model_class, register_id,
                                        register)
            rules << rule if rule
          end

          # Compile attribute mappings
          mapping_dsl.attributes.each do |mapping_rule|
            rule = compile_attribute_rule(mapping_rule, model_class,
                                          register_id, register)
            rules << rule if rule
          end

          # Compile content mapping if present
          if mapping_dsl.content_mapping
            rule = compile_content_rule(mapping_dsl.content_mapping,
                                        model_class, register_id)
            rules << rule if rule
          end

          # Compile raw mapping (map_all directive) if present
          if mapping_dsl.raw_mapping
            rule = compile_raw_rule(mapping_dsl.raw_mapping, model_class,
                                    register_id)
            rules << rule if rule
          end

          # Add a pseudo-rule for root namespace if present
          # This ensures root namespace is included in all_namespaces
          if mapping_dsl.namespace_class
            rules << ::Lutaml::Model::CompiledRule.new(
              attribute_name: :__root_namespace__,
              serialized_name: "__root__",
              namespace_class: mapping_dsl.namespace_class,
              mapping_type: :root_namespace,
            )
          end

          rules.compact
        end

        # Compile an element mapping rule
        #
        # @param mapping_rule [Xml::MappingRule] The mapping rule to compile
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @param register [Register, nil] The register object
        # @return [CompiledRule, nil] Compiled rule or nil
        def compile_element_rule(mapping_rule, model_class, register_id,
register)
          # Access custom_methods early to check if we need to infer attribute name
          custom_methods_value = mapping_rule.custom_methods

          # Get attribute name from mapping rule, or infer from custom methods
          attr_name = infer_attribute_name(mapping_rule, custom_methods_value,
                                           model_class, register_id)
          return nil unless attr_name

          # Handle delegated attributes
          if mapping_rule.delegate
            return compile_delegated_element_rule(
              mapping_rule, model_class, register_id, register,
              attr_name, custom_methods_value
            )
          end

          # Get attribute definition from model class (non-delegated)
          attr = model_class.attributes(register_id)&.[](attr_name)

          # For custom methods without a real attribute, create the rule anyway
          if attr.nil? && !custom_methods_value.empty?
            return compile_custom_method_element_rule(
              mapping_rule, attr_name, custom_methods_value
            )
          end

          return nil unless attr

          compile_standard_element_rule(mapping_rule, attr, attr_name,
                                        register_id, register, custom_methods_value)
        end

        # Compile an attribute mapping rule
        #
        # @param mapping_rule [Xml::MappingRule] The mapping rule to compile
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @param register [Register, nil] The register object
        # @return [CompiledRule, nil] Compiled rule or nil
        def compile_attribute_rule(mapping_rule, model_class, register_id,
_register)
          # Access custom_methods early to check if we need to infer attribute name
          custom_methods_value = mapping_rule.custom_methods

          # Get attribute name from mapping rule, or infer from custom methods
          attr_name = infer_attribute_name(mapping_rule, custom_methods_value,
                                           model_class, register_id)
          return nil unless attr_name

          # Handle delegated attributes
          if mapping_rule.delegate
            return compile_delegated_attribute_rule(
              mapping_rule, model_class, register_id,
              attr_name, custom_methods_value
            )
          end

          # Get attribute definition from model class (non-delegated)
          attr = model_class.attributes(register_id)&.[](attr_name)

          # For custom methods without a real attribute, create the rule anyway
          if attr.nil? && !custom_methods_value.empty?
            return compile_custom_method_attribute_rule(
              mapping_rule, attr_name, custom_methods_value
            )
          end

          return nil unless attr

          compile_standard_attribute_rule(mapping_rule, attr, attr_name,
                                          register_id, custom_methods_value)
        end

        # Compile a content mapping rule
        #
        # @param mapping_rule [Xml::MappingRule] The content mapping rule
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @return [CompiledRule, nil] Compiled rule or nil
        def compile_content_rule(mapping_rule, model_class, register_id)
          custom_methods_value = mapping_rule.custom_methods

          # Get attribute name from mapping rule, or use placeholder for custom methods
          attr_name = mapping_rule.to
          if (attr_name.nil? || (attr_name.respond_to?(:empty?) && attr_name.empty?)) && !custom_methods_value.empty?
            attr_name = :__content__
          end

          return nil unless attr_name

          attr = model_class.attributes(register_id)&.[](attr_name)

          # For custom methods without a real attribute
          if attr.nil? && !custom_methods_value.empty?
            return build_content_rule(mapping_rule, attr_name, nil,
                                      custom_methods_value)
          end

          return nil unless attr

          build_content_rule(mapping_rule, attr_name, attr.type(register_id),
                             nil)
        end

        # Compile a raw mapping rule (map_all directive)
        #
        # @param mapping_rule [Xml::MappingRule] The raw mapping rule
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @return [CompiledRule, nil] Compiled rule or nil
        def compile_raw_rule(mapping_rule, model_class, register_id)
          attr_name = mapping_rule.to
          return nil unless attr_name

          attr = model_class.attributes(register_id)&.[](attr_name)
          return nil unless attr

          value_transformer = build_value_transformer(mapping_rule, attr)
          value_map = mapping_rule.instance_variable_get(:@value_map)

          ::Lutaml::Model::CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: nil,
            attribute_type: attr.type(register_id),
            value_transformer: value_transformer,
            mapping_type: :raw,
            render_nil: mapping_rule.render_nil,
            render_default: mapping_rule.render_default,
            render_empty: mapping_rule.render_empty,
            value_map: value_map,
            custom_methods: mapping_rule.custom_methods,
          )
        end

        # Build child transformation for nested model
        #
        # @param type_class [Class] The nested model class
        # @param register [Register, nil] The register
        # @return [Transformation, nil] Child transformation or nil
        def build_child_transformation(type_class, register)
          return nil unless type_class.is_a?(Class) && type_class.include?(Lutaml::Model::Serialize)

          type_class.transformation_for(:xml, register)
        end

        # Build value transformer from mapping rule and attribute
        #
        # @param mapping_rule [Xml::MappingRule] The mapping rule
        # @param attr [Attribute, nil] The attribute definition (nil for custom methods)
        # @return [Proc, Hash, nil] Value transformer
        def build_value_transformer(mapping_rule, attr)
          mapping_transform = mapping_rule.transform

          attr_transform = if attr.nil?
                             nil
                           elsif attr.respond_to?(:transform)
                             attr.transform
                           elsif attr.options
                             attr.options[:transform]
                           end

          if mapping_transform && !mapping_transform.empty?
            return mapping_transform
          end

          if attr_transform && !attr_transform.empty?
            return attr_transform
          end

          nil
        end

        private

        # Infer attribute name from mapping rule or custom methods
        #
        # @param mapping_rule [Xml::MappingRule] The mapping rule
        # @param custom_methods_value [Hash] Custom methods hash
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @return [Symbol, nil] Inferred attribute name or nil
        def infer_attribute_name(mapping_rule, custom_methods_value,
model_class, register_id)
          attr_name = mapping_rule.to
          if (attr_name.nil? || (attr_name.respond_to?(:empty?) && attr_name.empty?)) && !custom_methods_value.empty?
            if mapping_rule.name
              names = mapping_rule.name.is_a?(Array) ? mapping_rule.name : [mapping_rule.name]
              matched = names.map(&:to_sym).find do |n|
                model_class.attributes(register_id)&.key?(n)
              end
              matched || (custom_methods_value[:to] ? names.first.to_sym : nil)
            end
          else
            attr_name
          end
        end

        # Compile delegated element rule
        def compile_delegated_element_rule(mapping_rule, model_class,
register_id, register, attr_name, custom_methods_value)
          delegate_target = mapping_rule.delegate

          delegate_attr = model_class.attributes(register_id)&.[](delegate_target)
          return nil unless delegate_attr

          delegate_class = delegate_attr.type(register_id)
          return nil unless delegate_class.is_a?(Class) &&
            delegate_class.include?(Lutaml::Model::Serialize)

          attr = delegate_class.attributes(register_id)&.[](attr_name)
          return nil unless attr

          attr_type = attr.type(register_id)
          child_transformation = if attr_type.is_a?(Class) &&
              attr_type < Lutaml::Model::Serialize
                                   build_child_transformation(attr_type,
                                                              register)
                                 end

          collection_info = { range: attr.options[:collection] } if attr.collection?

          namespace_class = mapping_rule.namespace_class
          if !namespace_class && attr_type.is_a?(Class) && attr_type.include?(Lutaml::Model::Serialize)
            namespace_class = attr_type.xml_namespace
          end

          value_transformer = build_value_transformer(mapping_rule, attr)
          value_map = mapping_rule.instance_variable_get(:@value_map)
          rule_name = mapping_rule.multiple_mappings? ? mapping_rule.name.first : mapping_rule.name

          ::Lutaml::Model::CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: rule_name.to_s,
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
            custom_methods: custom_methods_value,
            polymorphic: mapping_rule.polymorphic,
            form: mapping_rule.form,
            delegate_from: delegate_target,
          )
        end

        # Compile custom method element rule (no real attribute)
        def compile_custom_method_element_rule(mapping_rule, attr_name,
custom_methods_value)
          value_transformer = build_value_transformer(mapping_rule, nil)
          value_map = mapping_rule.instance_variable_get(:@value_map)
          rule_name = mapping_rule.multiple_mappings? ? mapping_rule.name.first : mapping_rule.name
          alias_names = mapping_rule.multiple_mappings? ? mapping_rule.name[1..].map(&:to_s) : nil

          ::Lutaml::Model::CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: rule_name.to_s,
            attribute_type: nil,
            child_transformation: nil,
            value_transformer: value_transformer,
            collection_info: nil,
            namespace_class: mapping_rule.namespace_class,
            mapping_type: :element,
            cdata: mapping_rule.cdata,
            mixed_content: mapping_rule.mixed_content?,
            raw: false,
            render_nil: mapping_rule.render_nil,
            render_default: mapping_rule.render_default,
            render_empty: mapping_rule.render_empty,
            value_map: value_map,
            custom_methods: custom_methods_value,
            polymorphic: mapping_rule.polymorphic,
            form: mapping_rule.form,
            alias_names: alias_names,
          )
        end

        # Compile standard element rule
        def compile_standard_element_rule(mapping_rule, attr, attr_name,
register_id, register, custom_methods_value)
          attr_type = attr.type(register_id)

          child_transformation = if attr_type.is_a?(Class) &&
              attr_type < Lutaml::Model::Serialize
                                   build_child_transformation(attr_type,
                                                              register)
                                 end

          collection_info = { range: attr.options[:collection] } if attr.collection?

          namespace_class = mapping_rule.namespace_class
          if !namespace_class && attr_type.respond_to?(:xml_namespace)
            namespace_class = attr_type.xml_namespace
          end

          value_transformer = build_value_transformer(mapping_rule, attr)
          value_map = mapping_rule.instance_variable_get(:@value_map)
          rule_name = mapping_rule.multiple_mappings? ? mapping_rule.name.first : mapping_rule.name
          alias_names = mapping_rule.multiple_mappings? ? mapping_rule.name[1..].map(&:to_s) : nil

          ::Lutaml::Model::CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: rule_name.to_s,
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
            custom_methods: custom_methods_value,
            polymorphic: mapping_rule.polymorphic,
            form: mapping_rule.form,
            alias_names: alias_names,
          )
        end

        # Compile delegated attribute rule
        def compile_delegated_attribute_rule(mapping_rule, model_class,
register_id, attr_name, custom_methods_value)
          delegate_target = mapping_rule.delegate

          delegate_attr = model_class.attributes(register_id)&.[](delegate_target)
          return nil unless delegate_attr

          delegate_class = delegate_attr.type(register_id)
          return nil unless delegate_class.is_a?(Class) &&
            delegate_class.include?(Lutaml::Model::Serialize)

          attr = delegate_class.attributes(register_id)&.[](attr_name)
          return nil unless attr

          attr_type = attr.type(register_id)

          namespace_class = mapping_rule.namespace_class
          if !namespace_class && attr_type.is_a?(Class) && attr_type.include?(Lutaml::Model::Serialize)
            namespace_class = attr_type.xml_namespace
          end

          value_transformer = build_value_transformer(mapping_rule, attr)
          value_map = mapping_rule.instance_variable_get(:@value_map)
          rule_name = mapping_rule.multiple_mappings? ? mapping_rule.name.first : mapping_rule.name
          alias_names = mapping_rule.multiple_mappings? ? mapping_rule.name[1..].map(&:to_s) : nil

          ::Lutaml::Model::CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: rule_name.to_s,
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
            delegate_from: delegate_target,
            custom_methods: custom_methods_value,
            alias_names: alias_names,
          )
        end

        # Compile custom method attribute rule (no real attribute)
        def compile_custom_method_attribute_rule(mapping_rule, attr_name,
custom_methods_value)
          value_transformer = build_value_transformer(mapping_rule, nil)
          value_map = mapping_rule.instance_variable_get(:@value_map)
          rule_name = mapping_rule.multiple_mappings? ? mapping_rule.name.first : mapping_rule.name
          alias_names = mapping_rule.multiple_mappings? ? mapping_rule.name[1..].map(&:to_s) : nil

          ::Lutaml::Model::CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: rule_name.to_s,
            attribute_type: nil,
            value_transformer: value_transformer,
            namespace_class: mapping_rule.namespace_class,
            mapping_type: :attribute,
            render_nil: mapping_rule.render_nil,
            render_default: mapping_rule.render_default,
            render_empty: mapping_rule.render_empty,
            value_map: value_map,
            as_list: mapping_rule.as_list,
            delimiter: mapping_rule.delimiter,
            custom_methods: custom_methods_value,
            alias_names: alias_names,
          )
        end

        # Compile standard attribute rule
        def compile_standard_attribute_rule(mapping_rule, attr, attr_name,
register_id, custom_methods_value)
          attr_type = attr.type(register_id)

          namespace_class = mapping_rule.namespace_class
          if !namespace_class && attr_type.respond_to?(:xml_namespace)
            namespace_class = attr_type.xml_namespace
          end

          value_transformer = build_value_transformer(mapping_rule, attr)
          value_map = mapping_rule.instance_variable_get(:@value_map)
          rule_name = mapping_rule.multiple_mappings? ? mapping_rule.name.first : mapping_rule.name
          alias_names = mapping_rule.multiple_mappings? ? mapping_rule.name[1..].map(&:to_s) : nil

          ::Lutaml::Model::CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: rule_name.to_s,
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
            custom_methods: custom_methods_value,
            alias_names: alias_names,
          )
        end

        # Build content rule
        def build_content_rule(mapping_rule, attr_name, attr_type,
custom_methods_value)
          value_transformer = build_value_transformer(mapping_rule, nil)
          value_map = mapping_rule.instance_variable_get(:@value_map)

          ::Lutaml::Model::CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: nil,
            attribute_type: attr_type,
            value_transformer: value_transformer,
            mapping_type: :content,
            cdata: mapping_rule.cdata,
            mixed_content: mapping_rule.mixed_content?,
            render_nil: mapping_rule.render_nil,
            render_default: mapping_rule.render_default,
            render_empty: mapping_rule.render_empty,
            value_map: value_map,
            custom_methods: custom_methods_value,
          )
        end
      end
    end
  end
end
