# frozen_string_literal: true

module Lutaml
  module KeyValue
    class Transformation
      # Compiles mapping DSL rules into pre-compiled transformation rules.
      #
      # This is an independent class with explicit dependencies that can be
      # tested in isolation from Transformation.
      #
      # @example Basic usage
      #   compiler = RuleCompiler.new(
      #     model_class: MyModel,
      #     register_id: :default,
      #     format: :json,
      #     transformation_factory: ->(type_class) { Transformation.new(type_class, ...) }
      #   )
      #   rules = compiler.compile(mapping_dsl)
      #
      class RuleCompiler
        # @return [Class] The model class being compiled
        attr_reader :model_class

        # @return [Symbol, nil] The register ID for attribute lookup
        attr_reader :register_id

        # @return [Symbol] The serialization format (:json, :yaml, :toml)
        attr_reader :format

        # @return [Proc] Factory lambda for creating child transformations
        attr_reader :transformation_factory

        # Initialize the RuleCompiler with explicit dependencies.
        #
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @param format [Symbol] The serialization format
        # @param transformation_factory [Proc] Factory lambda ->(type_class) { Transformation }
        def initialize(model_class:, register_id:, format:,
transformation_factory:)
          @model_class = model_class
          @register_id = register_id
          @format = format
          @transformation_factory = transformation_factory
        end

        # Compile key-value mapping DSL into pre-compiled rules.
        #
        # This is the main entry point for rule compilation.
        #
        # @param mapping_dsl [Mapping::KeyValueMapping] The mapping to compile
        # @return [Array<CompiledRule>] Array of compiled transformation rules
        def compile(mapping_dsl)
          return [] unless mapping_dsl

          rules = []

          # Compile all mappings (key-value formats don't distinguish elements/attributes)
          mappings_to_compile = if @register_id && @register_id != :default &&
              mapping_dsl.mappings(@register_id).any?
                                  mapping_dsl.mappings(@register_id)
                                else
                                  mapping_dsl.mappings
                                end
          mappings_to_compile.each do |mapping_rule|
            rule = compile_rule(mapping_rule, mapping_dsl)
            rules << rule if rule
          end

          rules.compact
        end

        # Compile a single mapping rule.
        #
        # @param mapping_rule [Mapping::KeyValueMappingRule] The mapping rule
        # @param mapping_dsl [Mapping::KeyValueMapping] The mapping DSL (for accessing key_mappings)
        # @return [CompiledRule, nil] Compiled rule or nil
        def compile_rule(mapping_rule, mapping_dsl)
          # Access custom_methods and delegate early to check how to compile this rule
          custom_methods = mapping_rule.instance_variable_get(:@custom_methods)
          delegate = mapping_rule.instance_variable_get(:@delegate)

          attr_name = mapping_rule.to

          # For rules with custom methods but no 'to' attribute (e.g., with: { to: ... }),
          # we need to find the attribute name from the mapping
          if attr_name.nil? && !custom_methods.empty?
            # Try to infer attribute name from 'name' or 'from'
            # For multiple_mappings, name is an array - check each element
            attr_name = if mapping_rule.name
                          names = mapping_rule.name.is_a?(Array) ? mapping_rule.name : [mapping_rule.name]
                          names.map(&:to_sym).find do |n|
                            model_class.attributes(register_id)&.key?(n)
                          end
                        elsif mapping_rule.from.is_a?(String) && model_class.attributes(register_id)&.key?(mapping_rule.from.to_sym)
                          mapping_rule.from.to_sym
                        end
          end

          # For custom methods without an inferred attribute, use a placeholder
          # The custom method will handle all serialization logic
          if attr_name.nil? && !custom_methods.empty?
            # Use serialized name as placeholder for attribute name
            # The custom method handles everything, so we don't need a real attribute
            # For multiple_mappings, use the first name element
            first_name = if mapping_rule.name.is_a?(Array)
                           mapping_rule.name.first
                         else
                           mapping_rule.name
                         end
            attr_name = first_name&.to_sym || :__custom_method__

            # Create a dummy attribute type for custom methods
            attr_type = nil
            child_transformation = nil
            collection_info = nil
            value_transformer = nil
          else
            return nil unless attr_name

            # For delegated attributes, get attribute from delegated object's class
            if delegate
              # Get the delegate attribute from model to find the delegated class
              delegate_attr = model_class.attributes(register_id)&.[](delegate)
              return nil unless delegate_attr

              # Get the delegated class type
              delegated_class = delegate_attr.type(register_id)
              return nil unless delegated_class

              # Get the actual attribute from the delegated class
              attr = delegated_class.attributes&.[](attr_name)
            else
              # Get attribute definition from model class
              attr = model_class.attributes(register_id)&.[](attr_name)
            end
            return nil unless attr

            # Get attribute type
            attr_type = attr.type(register_id)

            # Build child transformation for nested models
            child_transformation = if attr_type.is_a?(Class) &&
                attr_type < Lutaml::Model::Serialize
                                     build_child_transformation(attr_type)
                                   end

            # Build collection info (include child_mappings for keyed collections)
            collection_info = if attr.collection?
                                info = { range: attr.options[:collection] }
                                # Add child_mappings if present (for map_key and map_value features)
                                # The keyed collection info might be stored in different places:
                                # 1. As child_mappings on the rule (from map_to_instance)
                                # 2. As @key_mappings on the mapping_dsl (separate __key_mapping entry)
                                # 3. As @value_mappings on the mapping_dsl (from map_value)
                                child_mappings_value = nil

                                # First try to get child_mappings from the rule
                                if mapping_rule.child_mappings
                                  child_mappings_value = mapping_rule.child_mappings
                                elsif mapping_rule.hash_mappings
                                  child_mappings_value = mapping_rule.hash_mappings
                                end

                                # If not found on the rule, check the mapping_dsl for @key_mappings or @value_mappings
                                if child_mappings_value.nil?
                                  # Check for @key_mappings (from map_key)
                                  key_mappings = mapping_dsl.instance_variable_get(:@key_mappings)
                                  if key_mappings
                                    # Extract the key attribute from the __key_mapping rule
                                    # The key_mappings has @to_instance which tells us which attribute is the key
                                    to_instance = key_mappings.instance_variable_get(:@to_instance)
                                    if to_instance
                                      # Create the child_mappings hash format: { id: :key }
                                      child_mappings_value = { to_instance.to_sym => :key }
                                    end
                                  end

                                  # Check for @value_mappings (from map_value)
                                  if child_mappings_value.nil?
                                    value_mappings = mapping_dsl.instance_variable_get(:@value_mapping)
                                    if value_mappings && !value_mappings.empty?
                                      # value_mappings is already in the correct format: { attr_name => :value }
                                      child_mappings_value = value_mappings
                                    end
                                  end
                                end

                                if child_mappings_value
                                  info[:child_mappings] =
                                    child_mappings_value
                                end
                                info
                              end

            # Build value transformer (use delegate_attr for delegated attributes)
            value_transformer = build_value_transformer(mapping_rule,
                                                        delegate ? delegate_attr : attr)
          end

          # Access value_map directly
          value_map = mapping_rule.instance_variable_get(:@value_map)

          # Check if this is a raw mapping (map_all directive)
          is_raw_mapping = mapping_rule.raw_mapping?

          # Get serialized name (key name in output)
          # For raw mappings, serialized_name is nil (content is merged directly)
          serialized_name = if is_raw_mapping
                              nil # Raw content has no key name
                            elsif !mapping_rule.name.nil?
                              # For multiple_mappings, use first element as serialized name
                              mapping_rule.name.is_a?(Array) ? mapping_rule.name.first.to_s : mapping_rule.name.to_s
                            elsif !mapping_rule.from.nil?
                              # For compatibility with multiple_mappings
                              mapping_rule.from.is_a?(Array) ? mapping_rule.from.first.to_s : mapping_rule.from.to_s
                            else
                              attr_name.to_s
                            end

          Lutaml::Model::CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: serialized_name,
            attribute_type: attr_type,
            child_transformation: child_transformation,
            value_transformer: value_transformer,
            collection_info: collection_info,
            mapping_type: is_raw_mapping ? :raw : :key_value,
            render_nil: mapping_rule.render_nil,
            render_default: mapping_rule.render_default,
            render_empty: mapping_rule.render_empty,
            value_map: value_map,
            custom_methods: custom_methods,
            delegate: delegate,
            root_mappings: mapping_rule.root_mappings,
          )
        end

        # Check if a mapping rule should be applied based on only/except options.
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

        private

        # Build child transformation for nested model.
        #
        # @param type_class [Class] The nested model class
        # @return [Transformation, nil] Child transformation or nil
        def build_child_transformation(type_class)
          return nil unless type_class.is_a?(Class) &&
            type_class.include?(Lutaml::Model::Serialize)

          transformation_factory.call(type_class)
        end

        # Build value transformer from mapping rule and attribute.
        #
        # @param mapping_rule [Mapping::KeyValueMappingRule] The mapping rule
        # @param attr [Attribute] The attribute definition
        # @return [Proc, Hash, nil] Value transformer
        def build_value_transformer(mapping_rule, attr)
          # Mapping-level transform takes precedence
          mapping_transform = mapping_rule.transform

          # Try to get attribute-level transform
          attr_transform = if attr.nil?
                             nil
                           else
                             attr.transform
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
      end
    end
  end
end
