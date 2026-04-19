# frozen_string_literal: true

module Lutaml
  module Xml
    module TransformationSupport
      # Module for serializing values to XML strings.
      #
      # Handles value serialization including:
      # - Boolean value_map mappings
      # - as_list and delimiter for array values
      # - Reference type serialization
      # - Custom Value type serialization (to_xml)
      # - Standard type serialization
      module ValueSerializer
        # Serialize a value to string for XML output
        #
        # @param value [Object] The value to serialize
        # @param rule [CompiledRule] The rule containing serialization options
        # @param model_class [Class] The model class for attribute lookup
        # @param register_id [Symbol, nil] The register ID
        # @return [String, nil] Serialized value or nil
        def serialize_value(value, rule, model_class, register_id)
          return nil if value.nil?
          return nil if Lutaml::Model::Utils.uninitialized?(value)

          # Handle boolean value_map for true: :empty
          # This MUST be checked before the Value type wrapping below
          # When boolean true maps to :empty, serialize as empty string (<Active/>)
          if value.is_a?(TrueClass) || value.is_a?(FalseClass)
            result = serialize_boolean_value(value, rule)
            return result if result.is_a?(String) || result.nil?
          end

          # Handle as_list and delimiter for array values BEFORE serialization
          # These features convert arrays to delimited strings for XML attributes
          if value.is_a?(Array)
            value = serialize_array_value(value, rule)
          end

          # For Reference types, use attribute's serialize method
          attr = find_attribute(model_class, rule.attribute_name, register_id)
          if attr && attr.unresolved_type == Lutaml::Model::Type::Reference
            return attr.serialize(value, :xml, register_id, {})
          end

          # For custom Value types with instance methods (to_xml, to_json, etc.)
          # wrap the value and call the instance method
          # NOTE: Skip to_xml for content mappings - content should preserve original value
          # for round-trip scenarios. Only attributes should use custom serialization.
          is_content_mapping = rule.option(:mapping_type) == :content
          if !is_content_mapping && custom_value_type?(rule.attribute_type)
            result = serialize_custom_value(value, rule.attribute_type)
            return result unless result.nil?
          end

          # Use type's serialization if available
          if rule.attribute_type.respond_to?(:serialize)
            rule.attribute_type.serialize(value)
          else
            value.to_s
          end
        end

        private

        # Serialize a boolean value with value_map support
        #
        # @param value [Boolean] The boolean value
        # @param rule [CompiledRule] The rule
        # @return [String, nil, false] Serialized value, nil, or false to continue
        def serialize_boolean_value(value, rule)
          value_map = rule.option(:value_map) || {}
          # Convert boolean to symbol key for hash access
          boolean_key = value ? true : false
          if value_map[:to] && value_map[:to][boolean_key]
            mapped_value = value_map[:to][boolean_key]
            return "" if mapped_value == :empty
            # For :omitted, return nil (caller will skip rendering)
            return nil if mapped_value == :omitted
          end
          false # Continue with normal serialization
        end

        # Serialize an array value using as_list or delimiter
        #
        # @param value [Array] The array value
        # @param rule [CompiledRule] The rule
        # @return [Object] The serialized value (may be string or original array)
        def serialize_array_value(value, rule)
          if rule.option(:as_list) && rule.option(:as_list)[:export]
            rule.option(:as_list)[:export].call(value)
          elsif rule.option(:delimiter)
            value.join(rule.option(:delimiter))
          else
            value
          end
        end

        # Check if type is a custom Value type
        #
        # @param attribute_type [Class, nil] The attribute type
        # @return [Boolean] true if custom Value type
        def custom_value_type?(attribute_type)
          attribute_type.respond_to?(:new) &&
            attribute_type < Lutaml::Model::Type::Value
        end

        # Serialize using custom Value type's to_xml method
        #
        # @param value [Object] The value
        # @param attribute_type [Class] The custom Value type
        # @return [String, nil] Serialized value or nil
        def serialize_custom_value(value, attribute_type)
          # Skip wrapping if value is already the correct type
          if value.is_a?(attribute_type) && value.respond_to?(:to_xml)
            return value.to_xml
          end

          wrapped_value = attribute_type.new(value)
          if wrapped_value.respond_to?(:to_xml)
            wrapped_value.to_xml
          end
        end

        # Find attribute definition from model class
        #
        # @param model_class [Class] The model class
        # @param attr_name [Symbol] The attribute name
        # @param register_id [Symbol, nil] The register ID
        # @return [Attribute, nil] The attribute or nil
        def find_attribute(model_class, attr_name, register_id)
          attr = model_class.attributes(register_id)&.[](attr_name)
          attr ||= model_class.attributes&.[](attr_name)
          attr
        end
      end
    end
  end
end
