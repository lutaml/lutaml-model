# frozen_string_literal: true

module Lutaml
  module Model
    module Serialize
      # Handles attribute definition methods for Serialize::ClassMethods
      #
      # Extracted from serialize.rb to improve code organization.
      # Provides methods for defining and validating model attributes.
      module AttributeDefinition
        # Define attribute methods on the model class
        #
        # @param attr [Attribute] The attribute to define methods for
        # @param register [Symbol, nil] The register for type resolution
        def define_attribute_methods(attr, register = nil)
          name = attr.name
          register_id = extract_register_id(register)

          if attr.enum?
            add_enum_methods_to_model(
              model,
              name,
              attr.options[:values],
              collection: attr.options[:collection],
            )
          elsif attr.derived? && name != attr.method_name
            unless method_defined?(name, false)
              define_method(name) do
                value = public_send(attr.method_name)
                # Cast the derived value to the specified type
                attr.cast_element(value, register_id)
              end
            end
          elsif attr.unresolved_type == Lutaml::Model::Type::Reference
            define_reference_methods(name, register_id)
          else
            define_regular_attribute_methods(name, attr)
          end
        end

        # Define reference-type attribute methods
        #
        # Reference types store a reference key that can be resolved to
        # the actual object.
        #
        # @param name [Symbol] The attribute name
        # @param register [Symbol] The register ID
        def define_reference_methods(name, register)
          register_id = register
          attr = attributes[name]

          unless method_defined?(:"#{name}_ref", false)
            define_method("#{name}_ref") do
              instance_variable_get(:"@#{name}_ref")
            end
          end

          key_method_name = if attr.options[:collection]
                              Utils.pluralize(attr.options[:ref_key_attribute].to_s)
                            else
                              attr.options[:ref_key_attribute]
                            end

          unless method_defined?(:"#{name}_#{key_method_name}", false)
            define_method("#{name}_#{key_method_name}") do
              ref = instance_variable_get(:"@#{name}_ref")
              resolve_reference_key(ref)
            end
          end

          unless method_defined?(name, false)
            define_method(name) do
              ref = instance_variable_get(:"@#{name}_ref")
              resolve_reference_value(ref)
            end
          end

          unless method_defined?(:"#{name}=", false)
            define_method(:"#{name}=") do |value|
              value_set_for(name)
              casted_value = value
              unless casted_value.is_a?(Lutaml::Model::Type::Reference)
                casted_value = attr.cast_value(value, register_id)
              end

              instance_variable_set(:"@#{name}_ref", casted_value)

              resolved_reference = resolve_reference_key(casted_value)
              instance_variable_set(:"@#{name}", resolved_reference)
            end
          end
        end

        # Define regular (non-reference, non-enum) attribute methods
        #
        # @param name [Symbol] The attribute name
        # @param attr [Attribute] The attribute definition
        def define_regular_attribute_methods(name, attr)
          # For collection attributes, the getter accepts an optional argument
          # for builder-style syntax: g.member(item) appends to the collection
          if attr.collection?
            define_method(name) do |*args|
              if args.empty?
                instance_variable_get(:"@#{name}")
              else
                # Builder-style: g.member(item) appends to collection
                value = args.first
                current = instance_variable_get(:"@#{name}") || []
                new_value = current.is_a?(Array) ? current + [value] : value
                instance_variable_set(:"@#{name}", new_value)
                # Track order for mixed_content serialization
                track_order(name, value, nil) if @__order_tracking__
                value
              end
            end
          else
            # For non-collection attributes, getter accepts optional argument
            # for builder-style syntax: g.description(value) sets the value
            define_method(name) do |*args|
              if args.empty?
                instance_variable_get(:"@#{name}")
              else
                # Builder-style: g.description(value) sets the value
                value = args.first
                send(:"#{name}=", value)
                # Track order for mixed_content serialization
                track_order(name, value, nil) if @__order_tracking__
                value
              end
            end
          end

          unless method_defined?(:"#{name}=", false)
            if attr.collection?
              define_method(:"#{name}=") do |value|
                value_set_for(name)
                value = attr.cast_value(value, lutaml_register)
                # Preserve the frozen sentinel when the deserialization pipeline
                # would overwrite it with nil/UninitializedClass (meaning "no data
                # found for this collection"). This maintains the zero-allocation
                # guarantee for unused collections. The sentinel is replaced with
                # a real Array only when actual data is set.
                current = instance_variable_get(:"@#{name}")
                if current.equal?(LAZY_EMPTY_COLLECTION) &&
                    (value.nil? || Lutaml::Model::Utils.uninitialized?(value))
                  # Sentinel stays — no allocation for truly empty collections
                else
                  instance_variable_set(:"@#{name}", value)
                end
              end
            else
              define_method(:"#{name}=") do |value|
                value_set_for(name)
                value = attr.cast_value(value, lutaml_register)
                instance_variable_set(:"@#{name}", value)
              end
            end
          end
        end

        # Define an attribute for the model
        #
        # @param name [Symbol] The attribute name
        # @param type [Class, Symbol, Hash] The attribute type
        # @param options [Hash] Attribute options
        # @return [Attribute] The created attribute
        def attribute(name, type, options = {})
          type, options = process_type_hash(type, options) if type.is_a?(::Hash)

          # Handle direct method option in options hash
          if options[:method]
            options[:method_name] = options.delete(:method)
          end

          attr = Attribute.new(name, type, options)
          @attributes[name] = attr
          define_attribute_methods(attr)

          attr
        end

        # Restrict options on an existing attribute
        #
        # @param name [Symbol] The attribute name to restrict
        # @param options [Hash] New options to merge
        # @return [Symbol] The attribute name
        def restrict(name, options = {})
          register_id = options.delete(:register) || Lutaml::Model::Config.default_register

          if !@attributes.key?(name) && !register_record(register_id)&.dig(
            :attributes, name
          )
            return restrict_attributes[name] = options if any_importable_models?

            raise Lutaml::Model::UndefinedAttributeError.new(name, self)
          end

          validate_attribute_options!(name, options)
          attr = attributes(register_id)[name]
          attr.options.merge!(options)
          attr.process_options!
          name
        end

        # Check if there are any importable models
        #
        # @return [Boolean] True if there are pending imports
        def any_importable_models?
          importable_choices.any? || importable_models.any?
        end

        # Validate attribute options
        #
        # @param name [Symbol] The attribute name
        # @param options [Hash] The options to validate
        # @raise [InvalidAttributeOptionsError] If invalid options are present
        def validate_attribute_options!(name, options)
          invalid_opts = options.keys - Attribute::ALLOWED_OPTIONS
          return if invalid_opts.empty?

          raise Lutaml::Model::InvalidAttributeOptionsError.new(name,
                                                                invalid_opts)
        end
      end
    end
  end
end
