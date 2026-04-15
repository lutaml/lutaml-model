# frozen_string_literal: true

module Lutaml
  module Model
    module Serialize
      # Handles value mapping methods for Serialize::ClassMethods
      #
      # Extracted from serialize.rb to improve code organization.
      # Provides methods for applying value maps and mappings.
      module ValueMapping
        # Apply mappings from a document to create a model instance
        #
        # @param doc [Hash, Object] The document to map from
        # @param format [Symbol] The format (:xml, :json, etc.)
        # @param options [Hash] Options including :register, :instance
        # @return [Object] The model instance with mapped values
        def apply_mappings(doc, format, options = {})
          register = options[:register] || Lutaml::Model::Config.default_register

          # Use child's own default register if it has one
          child_register = Utils.resolve_child_register(model, register)

          # For blank documents, return a bare instance without going
          # through data_to_model (which would create a duplicate instance).
          if Utils.blank?(doc)
            if options.key?(:instance)
              return options[:instance]
            elsif model.include?(Lutaml::Model::Serialize)
              return model.new({ lutaml_register: child_register })
            else
              object = model.new
              register_accessor_methods_for(object, child_register)
              return object
            end
          end

          mappings = mappings_for(format, register)

          if mappings.polymorphic_mapping
            instance = if model.include?(Lutaml::Model::Serialize)
                         model.new({ lutaml_register: child_register })
                       else
                         model.new
                       end
            return resolve_polymorphic(doc, format, mappings, instance, options)
          end

          transformer = Lutaml::Model::Config.transformer_for(format)
          transformer.data_to_model(self, doc, format, options)
        end

        # Resolve a polymorphic type from a document
        #
        # @param doc [Hash] The document to resolve from
        # @param format [Symbol] The format
        # @param mappings [Mapping] The mappings object
        # @param instance [Object] The base instance
        # @param options [Hash] Additional options
        # @return [Object] The resolved model instance
        def resolve_polymorphic(doc, format, mappings, instance, options = {})
          polymorphic_mapping = mappings.polymorphic_mapping
          return instance if polymorphic_mapping.polymorphic_map.empty?

          klass_key = doc[polymorphic_mapping.name]
          klass_name = polymorphic_mapping.polymorphic_map[klass_key]
          klass = Object.const_get(klass_name)

          klass.apply_mappings(doc, format,
                               options.merge(register: instance.lutaml_register))
        end

        # Apply a value map to transform a value
        #
        # Handles nil, empty, and omitted values according to the value map.
        #
        # @param value [Object] The value to transform
        # @param value_map [Hash] The value map configuration
        # @param attr [Attribute] The attribute definition
        # @return [Object] The transformed value
        def apply_value_map(value, value_map, attr)
          if value.nil?
            value_for_option(value_map[:nil], attr)
          elsif Utils.empty?(value)
            # Check for new boolean value_map format (from: { empty: true/false })
            # Only use new format if the value is explicitly boolean (TrueClass or FalseClass)
            if value_map[:from] && (value_map[:from][:empty].is_a?(TrueClass) || value_map[:from][:empty].is_a?(FalseClass))
              return value_map[:from][:empty]
            end
            # Check for direct boolean format (rule.value_map(:from) returns { empty: true })
            # Only return directly if it's a boolean value (TrueClass/FalseClass), not a symbol
            if value_map[:empty].is_a?(TrueClass) || value_map[:empty].is_a?(FalseClass)
              return value_map[:empty]
            end

            # Fall back to legacy value_map format
            value_for_option(value_map[:empty], attr, value)
          elsif Utils.uninitialized?(value)
            # Check for new boolean value_map format (from: { omitted: true/false })
            # Only use new format if the value is explicitly boolean (TrueClass or FalseClass)
            if value_map[:from] && (value_map[:from][:omitted].is_a?(TrueClass) || value_map[:from][:omitted].is_a?(FalseClass))
              return value_map[:from][:omitted]
            end
            # Check for direct boolean format (rule.value_map(:from) returns { omitted: false })
            # Only return directly if it's a boolean value (TrueClass/FalseClass), not a symbol
            if value_map[:omitted].is_a?(TrueClass) || value_map[:omitted].is_a?(FalseClass)
              return value_map[:omitted]
            end

            # Fall back to legacy value_map format
            value_for_option(value_map[:omitted], attr)
          else
            value
          end
        end

        # Get the value for a specific option in a value map
        #
        # @param option [Symbol] The option (:nil, :empty, etc.)
        # @param attr [Attribute] The attribute definition
        # @param empty_value [Object] The empty value to use (optional)
        # @return [Object, nil, UninitializedClass] The appropriate value
        def value_for_option(option, attr, empty_value = nil)
          return nil if option == :nil
          return empty_value || empty_object(attr) if option == :empty

          Lutaml::Model::UninitializedClass.instance
        end

        # Get an empty object for an attribute
        #
        # @param attr [Attribute] The attribute definition
        # @return [String, Array] Empty string or collection
        def empty_object(attr)
          return attr.build_collection if attr.collection?

          ""
        end

        # Ensure a value is UTF-8 encoded
        #
        # @param value [Object] The value to encode
        # @return [Object] The UTF-8 encoded value
        def ensure_utf8(value)
          case value
          when String
            value.encode("UTF-8", invalid: :replace, undef: :replace,
                                  replace: "")
          when Array
            value.map { |v| ensure_utf8(v) }
          when ::Hash
            value.transform_keys do |k|
              ensure_utf8(k)
            end.transform_values do |v|
              ensure_utf8(v)
            end
          else
            value
          end
        end

        # Register accessor methods on an object
        #
        # @param object [Object] The object to add methods to
        # @param register [Symbol] The register ID
        def register_accessor_methods_for(object, register)
          Utils.add_singleton_method_if_not_defined(object, :lutaml_register) do
            @lutaml_register
          end
          Utils.add_singleton_method_if_not_defined(object,
                                                    :lutaml_register=) do |value|
            @lutaml_register = value
          end
          object.lutaml_register = register
        end

        # Extract register ID from various formats
        #
        # Resolution order:
        # 1. Explicit register parameter
        # 2. Class instance variable @register (set by set_register_context via registration)
        # 3. Class's lutaml_default_register (for versioned schemas)
        # 4. Global Config.default_register
        #
        # @param register [Symbol, Register, nil] The register
        # @return [Symbol, nil] The register ID
        def extract_register_id(register)
          if register
            register.is_a?(Lutaml::Model::Register) ? register.id : register
          elsif instance_variable_defined?(:@register)
            instance_variable_get(:@register)
          else
            lutaml_default_register || Lutaml::Model::Config.default_register
          end
        end
      end
    end
  end
end
