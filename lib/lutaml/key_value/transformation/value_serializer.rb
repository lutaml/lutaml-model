# frozen_string_literal: true

module Lutaml
  module KeyValue
    class Transformation
      # Serializes values (primitives and nested models) for key-value formats.
      #
      # This is an independent class with explicit dependencies that can be
      # tested in isolation from Transformation.
      #
      # @example Basic usage
      #   serializer = ValueSerializer.new(
      #     format: :json,
      #     register_id: :default,
      #     transformation_factory: ->(type) { Transformation.new(type, ...) }
      #   )
      #   result = serializer.serialize_item(value, rule, options)
      #
      class ValueSerializer
        include Lutaml::Model::RenderPolicy

        # @return [Symbol] The serialization format (:json, :yaml, :toml)
        attr_reader :format

        # @return [Symbol, nil] The register ID for attribute lookup
        attr_reader :register_id

        # @return [Proc] Factory lambda for creating child transformations
        attr_reader :transformation_factory

        # @return [Class, nil] The model class for attribute lookup
        attr_reader :model_class

        # Initialize the ValueSerializer with explicit dependencies.
        #
        # @param format [Symbol] The serialization format
        # @param register_id [Symbol, nil] The register ID
        # @param transformation_factory [Proc] Factory lambda ->(type_class) { Transformation }
        # @param model_class [Class, nil] The model class for attribute lookup
        def initialize(format:, register_id:, transformation_factory:, model_class: nil)
          @format = format
          @register_id = register_id
          @transformation_factory = transformation_factory
          @model_class = model_class
        end

        # Serialize a value for an item (handles nested models and primitives).
        #
        # This is the main entry point for value serialization.
        #
        # @param value [Object] The value to serialize
        # @param rule [CompiledRule] The compiled rule
        # @param options [Hash] Serialization options
        # @return [Object, nil] The serialized value (Hash, primitive, or nil)
        def serialize_item(value, rule, options = {})
          return nil if value.nil?
          return nil if Lutaml::Model::Utils.uninitialized?(value)

          # Check for Reference type first - even if value is a Serializable,
          # it should be serialized as a key, not as a nested model
          if reference_type?(rule)
            return serialize_reference(value, rule)
          end

          if nested_model?(rule)
            serialize_nested_model(value, rule, options)
          else
            serialize_primitive(value, rule)
          end
        end

        # Check if a value is a nested model based on the rule.
        #
        # @param rule [CompiledRule] The compiled rule
        # @return [Boolean] true if the rule defines a nested model
        def nested_model?(rule)
          rule.attribute_type.is_a?(Class) &&
            rule.attribute_type < Lutaml::Model::Serialize ? true : false
        end

        # Serialize a nested model to a hash representation.
        #
        # @param value [Object] The model instance to serialize
        # @param rule [CompiledRule] The compiled rule
        # @param options [Hash] Serialization options
        # @return [Hash, nil] The serialized hash or nil if empty
        def serialize_nested_model(value, rule, options = {})
          validate_nested_model_type!(value, rule)

          # Determine the actual type for polymorphism support
          actual_type = determine_actual_type(value, rule)
          uses_polymorphism = actual_type != rule.attribute_type

          # Get or create child transformation
          child_transformation = if uses_polymorphism
                                   create_transformation(actual_type)
                                 else
                                   rule.child_transformation ||
                                     create_transformation(rule.attribute_type)
                                 end

          if child_transformation
            transform_nested_model(value, child_transformation, options)
          else
            serialize_primitive(value, rule)
          end
        end

        # Serialize a primitive value to the appropriate representation.
        #
        # @param value [Object] The primitive value
        # @param rule [CompiledRule] The compiled rule
        # @return [Object] The serialized value
        def serialize_primitive(value, rule)
          return nil if value.nil?
          return nil if Lutaml::Model::Utils.uninitialized?(value)

          # For Reference types, use attribute's serialize method
          if reference_type?(rule)
            return serialize_reference(value, rule)
          end

          # For Serializable types, use to_#{format} method
          if rule.attribute_type.is_a?(Class) &&
             rule.attribute_type < Lutaml::Model::Serialize
            validate_serializable_type!(value, rule)
            return value.send(:"to_#{format}")
          end

          # Wrap value in type and call to_#{format}
          if rule.attribute_type.respond_to?(:new)
            wrapped_value = rule.attribute_type.new(value)
            wrapped_value.send(:"to_#{format}")
          else
            value
          end
        end

        private

        # Validate that a nested model value matches the expected type.
        #
        # @param value [Object] The value to validate
        # @param rule [CompiledRule] The compiled rule
        # @raise [Lutaml::Model::IncorrectModelError] if type mismatch
        def validate_nested_model_type!(value, rule)
          context = Lutaml::Model::GlobalContext.context(register_id)
          subs = context.substitution_for(rule.attribute_type)
          uses_type_substitution = subs.any? { |s| s.to_type == value.class }

          if rule.attribute_type.respond_to?(:model) && rule.attribute_type.model
            # Mapper class: value should be an instance of the mapped model
            unless value.is_a?(rule.attribute_type.model) || uses_type_substitution
              msg = "attribute '#{rule.attribute_name}' value is a '#{value.class}' " \
                    "but should be a '#{rule.attribute_type.model}'"
              raise Lutaml::Model::IncorrectModelError, msg
            end
          else
            # Regular Serializable class
            unless value.is_a?(Lutaml::Model::Serialize) || uses_type_substitution
              msg = "attribute '#{rule.attribute_name}' value is a '#{value.class}' " \
                    "but should be a kind of 'Lutaml::Model::Serialize'"
              raise Lutaml::Model::IncorrectModelError, msg
            end
          end
        end

        # Validate that a Serializable value matches the expected type.
        #
        # @param value [Object] The value to validate
        # @param rule [CompiledRule] The compiled rule
        # @raise [Lutaml::Model::IncorrectModelError] if type mismatch
        def validate_serializable_type!(value, rule)
          unless value.is_a?(rule.attribute_type)
            msg = "attribute '#{rule.attribute_name}' value is a '#{value.class}' " \
                  "but should be a '#{rule.attribute_type}'"
            raise Lutaml::Model::IncorrectModelError, msg
          end
        end

        # Determine the actual type for polymorphism support.
        #
        # @param value [Object] The value
        # @param rule [CompiledRule] The compiled rule
        # @return [Class] The actual type to use
        def determine_actual_type(value, rule)
          context = Lutaml::Model::GlobalContext.context(register_id)
          subs = context.substitution_for(rule.attribute_type)
          uses_type_substitution = subs.any? { |s| s.to_type == value.class }

          if (value.class < rule.attribute_type) || uses_type_substitution
            value.class
          else
            rule.attribute_type
          end
        end

        # Create a transformation for a type class.
        #
        # @param type_class [Class] The type class
        # @return [Transformation] The transformation instance
        def create_transformation(type_class)
          transformation_factory.call(type_class)
        end

        # Transform a nested model using the child transformation.
        #
        # @param value [Object] The model instance
        # @param child_transformation [Transformation] The child transformation
        # @param options [Hash] Serialization options
        # @return [Hash, nil] The serialized hash or nil if empty
        def transform_nested_model(value, child_transformation, options)
          child_root = child_transformation.transform(value, options)
          child_hash = child_root.to_hash
          result = child_hash["__root__"]

          # Return nil for empty hashes (allows render_nil: false to work)
          result.nil? || result.empty? ? nil : result
        end

        # Check if the rule defines a Reference type.
        #
        # @param rule [CompiledRule] The compiled rule
        # @return [Boolean] true if Reference type
        def reference_type?(rule)
          return false unless rule.respond_to?(:attribute_name)
          return false unless model_class

          # Get the attribute from the model class to check unresolved_type
          attr = model_class.attributes(register_id)&.[](rule.attribute_name)
          attr ||= model_class.attributes&.[](rule.attribute_name)

          attr && attr.unresolved_type == Lutaml::Model::Type::Reference
        end

        # Serialize a Reference type value.
        #
        # @param value [Object] The value to serialize
        # @param rule [CompiledRule] The compiled rule
        # @return [Object] The serialized reference (the key)
        def serialize_reference(value, rule)
          return value if value.nil?

          # Get the attribute from model_class to use its serialize method
          if model_class
            attr = model_class.attributes(register_id)&.[](rule.attribute_name)
            attr ||= model_class.attributes&.[](rule.attribute_name)

            if attr
              return attr.serialize(value, format, register_id, {})
            end
          end

          # Fallback: just call to_format on the value
          if value.respond_to?(:"to_#{format}")
            value.send(:"to_#{format}")
          else
            value
          end
        end
      end
    end
  end
end
