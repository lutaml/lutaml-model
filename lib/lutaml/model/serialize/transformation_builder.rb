# frozen_string_literal: true

module Lutaml
  module Model
    module Serialize
      # Handles transformation building for Serialize::ClassMethods
      #
      # Extracted from serialize.rb to improve code organization.
      # Provides methods for building transformations and processing types.
      module TransformationBuilder
        # Get or build a pre-compiled transformation for the specified format
        #
        # Transformations are cached centrally in TransformationRegistry singleton
        # to ensure compilation happens only once per model class and format.
        #
        # CRITICAL: Uses TransformationRegistry for cycle detection to prevent
        # infinite recursion on self-referential models (e.g., Address.address: Address)
        #
        # Architecture (Phase 5.1 refactoring):
        # - Model classes define mappings (declarative DSL) - stateless
        # - TransformationRegistry manages ALL transformation caches - single source of truth
        # - Transformation objects execute serialization - runtime instances
        #
        # Register resolution: If the caller passes a parent register (e.g., :default)
        # but this class declares its own `lutaml_default_register` (e.g., :mml_v2),
        # the child's register takes precedence. This ensures cross-register embedding
        # works transparently — the parent doesn't need to know the child's register.
        #
        # @param format [Symbol] The format (:xml, :json, :yaml, etc.)
        # @param register [Symbol, Register, nil] The register for type resolution
        # @return [Transformation, nil] The pre-compiled transformation, or nil if cycle detected
        def transformation_for(format, register = nil)
          resolved_register = Lutaml::Model::Register.resolve_for_child(self,
                                                                        register)
          TransformationRegistry.instance.get_or_build_transformation(self,
                                                                      format, resolved_register)
        end

        # Build a new transformation instance for the format
        #
        # This method creates a pre-compiled transformation by:
        # 1. Ensuring all mappings are imported
        # 2. Getting the mapping DSL for the format
        # 3. Creating format-specific transformation class
        #
        # @param format [Symbol] The format (:xml, :json, :yaml, etc.)
        # @param register_id [Symbol] The register ID
        # @return [Transformation] The transformation instance
        def build_transformation(format, register_id)
          # Get the mapping DSL for this format
          mapping_dsl = mappings_for(format, register_id)

          # Pass register_id directly (Attribute#type handles Symbol)

          # Create format-specific transformation using registered builders
          # XML builder is registered by Lutaml::Xml at load time via
          # TransformationRegistry.register_builder(:xml, ...)
          case format
          when :json, :yaml, :toml, :hash
            # Key-value formats use KeyValue::Transformation (symmetric OOP architecture)
            Lutaml::KeyValue::Transformation.new(self, mapping_dsl,
                                                 format, register_id)
          else
            # For other formats (including :xml), use registered builder or return mapping_dsl
            builder = TransformationRegistry.builder_for(format)
            if builder
              builder.build(self, mapping_dsl, format, register_id)
            else
              mapping_dsl
            end
          end
        end

        # Process a type hash (for reference types)
        #
        # @param type [Hash] The type specification
        # @param options [Hash] The options hash to update
        # @return [Array] Tuple of [type, options]
        def process_type_hash(type, options)
          if reference_type?(type)
            type, options = process_reference_type(type, options)
          else
            type = nil
          end

          [type, options]
        end

        # Check if a type hash specifies a reference type
        #
        # @param type [Hash] The type specification
        # @return [Boolean] True if this is a reference type
        def reference_type?(type)
          type.key?(:ref) || type.key?("ref")
        end

        # Process a reference type specification
        #
        # @param type [Hash] The type specification
        # @param options [Hash] The options hash to update
        # @return [Array] Tuple of [type, options]
        def process_reference_type(type, options)
          ref_spec = type[:ref] || type["ref"]
          validate_reference_spec!(ref_spec)

          model_class, key_attr = ref_spec
          options[:ref_model_class] = model_class
          options[:ref_key_attribute] = key_attr
          type = Lutaml::Model::Type::Reference

          [type, options]
        end

        # Validate a reference specification
        #
        # @param ref_spec [Object] The reference specification
        # @raise [ArgumentError] If the specification is invalid
        def validate_reference_spec!(ref_spec)
          return if ref_spec.is_a?(Array) && ref_spec.length == 2

          raise ArgumentError,
                "ref: syntax requires an array [model_class, key_attribute]"
        end
      end
    end
  end
end
