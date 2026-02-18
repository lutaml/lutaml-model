# frozen_string_literal: true

require "set"
require_relative "global_register"
require_relative "register"
require_relative "transformation_builder"
require_relative "xml_transformation_builder"
require_relative "key_value_transformation_builder"

module Lutaml
  module Model
    # Registry for managing transformation lifecycle and caching.
    #
    # This registry is the single source of truth for all transformation
    # instances and resolved mappings. It provides:
    #
    # 1. Centralized caching - both transformations and mappings
    # 2. Thread safety - Mutex-protected access
    # 3. Cycle detection - handles self-referential models (e.g., Address.address: Address)
    # 4. Single responsibility - manages transformation lifecycle only
    # 5. Open/Closed - extensible via builder registration
    #
    # Architecture layers:
    # - Configuration (Model classes): Define mappings (stateless DSL)
    # - Compilation (TransformationBuilder): Build transformation (stateless) <- NEW
    # - Registry (TransformationRegistry): Cache and lifecycle (stateful service) <- THIS
    # - Execution (Transformation): Serialize data (stateful instances)
    #
    # @example Adding a custom format builder
    #   class ProtobufBuilder < TransformationBuilder
    #     def self.build(model_class, mapping, format, register)
    #       Protobuf::Transformation.new(model_class, mapping, format, register)
    #     end
    #   end
    #
    #   TransformationRegistry.register_builder(:protobuf, ProtobufBuilder)
    class TransformationRegistry
      # Default builders for built-in formats
      DEFAULT_BUILDERS = {
        xml: XmlTransformationBuilder,
        json: KeyValueTransformationBuilder,
        yaml: KeyValueTransformationBuilder,
        toml: KeyValueTransformationBuilder,
        hash: KeyValueTransformationBuilder,
      }.freeze

      class << self
        # Get singleton instance
        def instance
          @instance ||= new
        end

        # Register a builder for a format.
        #
        # This allows extending TransformationRegistry with new formats
        # without modifying its code (Open/Closed Principle).
        #
        # @param format [Symbol] The format to register (e.g., :protobuf)
        # @param builder [Class] A class that inherits from TransformationBuilder
        # @return [void]
        #
        # @example
        #   TransformationRegistry.register_builder(:protobuf, ProtobufBuilder)
        def register_builder(format, builder)
          unless builder < TransformationBuilder
            raise ArgumentError,
                  "Builder must inherit from TransformationBuilder"
          end

          @builders ||= DEFAULT_BUILDERS.dup
          @builders[format] = builder
        end

        # Get the registered builder for a format.
        #
        # @param format [Symbol] The format
        # @return [Class, nil] The builder class or nil
        def builder_for(format)
          @builders ||= DEFAULT_BUILDERS.dup
          @builders[format]
        end

        # Reset builders to defaults (useful for testing)
        #
        # @return [void]
        def reset_builders!
          @builders = DEFAULT_BUILDERS.dup
        end
      end

      def initialize
        @transformations = {}  # Cache for transformation instances
        @mappings = {}         # Cache for resolved mappings
        @mutex = Mutex.new
      end

      # Get or build transformation for a model class and format.
      #
      # This method provides cycle detection for self-referential models.
      # When a transformation is being built, it's marked with :building
      # to prevent infinite recursion.
      #
      # @param model_class [Class] The model class (e.g., Person, Address)
      # @param format [Symbol] The format (:xml, :json, :yaml, :hash, :toml)
      # @param register [Symbol, Register, nil] The register for type resolution
      # @return [Transformation, nil] The transformation, or nil if cycle detected
      def get_or_build_transformation(model_class, format, register)
        key = transformation_key(model_class, format, register)

        @mutex.synchronize do
          # Return cached if available
          cached = @transformations[key]
          return cached if cached && cached != :building

          # Check for cycles (self-referential models)
          return nil if cached == :building

          # Mark as building to detect cycles
          @transformations[key] = :building
        end

        # Build transformation OUTSIDE the lock to avoid deadlock
        # (building may trigger recursive calls to get_or_build_transformation)
        mapping = get_or_build_mapping(model_class, format, register)
        transformation = build_transformation(model_class, mapping, format,
                                              register)

        # Cache and return the result
        @mutex.synchronize do
          @transformations[key] = transformation
        end

        transformation
      end

      # Get or build resolved mapping for a model class and format.
      #
      # This method caches the resolved mapping (either from mappings[format]
      # or from default_mappings(format)).
      #
      # CRITICAL: Ensures mappings are imported before returning, which handles
      # deferred symbol-based imports (e.g., import_model :SomeModel).
      #
      # NOTE: Building is done OUTSIDE the mutex to avoid deadlock when
      # ensure_mappings_imported! recursively calls mappings_for.
      #
      # @param model_class [Class] The model class
      # @param format [Symbol] The format
      # @param register [Symbol, Register, nil] The register
      # @return [Mapping] The resolved mapping
      def get_or_build_mapping(model_class, format, register)
        key = mapping_key(model_class, format, register)

        # Fast path: check if already cached
        return @mappings[key] if @mappings.key?(key)

        # Build mapping OUTSIDE the mutex to avoid deadlock
        # (ensure_mappings_imported! may recursively call mappings_for)
        mapping = model_class.mappings[format]
        mapping = mapping || model_class.send(:default_mappings, format)

        # Ensure mappings are imported (handles deferred symbol-based imports)
        register_id = extract_register_id(register)
        if mapping.respond_to?(:ensure_mappings_imported!)
          mapping.ensure_mappings_imported!(register_id)
        end

        # Store in cache (thread-safe)
        @mutex.synchronize do
          @mappings[key] ||= mapping
        end
      end

      # Clear all cached data (transformations and mappings).
      #
      # This is useful for testing or when configuration changes dynamically.
      def clear
        @mutex.synchronize do
          @transformations.clear
          @mappings.clear
        end
      end

      private

      # Build unique key for transformation cache
      #
      # IMPORTANT: Always include object_id to ensure uniqueness for classes
      # with the same name. This is necessary because tests can define multiple
      # classes with identical names (e.g., both returning "Vcard").
      #
      # @param model_class [Class] The model class
      # @param format [Symbol] The format
      # @param register [Symbol, Register, nil] The register
      # @return [Symbol] Unique cache key
      def transformation_key(model_class, format, register)
        register_id = extract_register_id(register)
        # Always include object_id to prevent cache pollution between classes
        # with the same name (common in test fixtures)
        class_name = model_class.name
        # For anonymous classes, name is nil or empty, use object_id only
        # For named classes, include both name and object_id for uniqueness
        class_id = if class_name.nil? || class_name.empty?
                     "0x#{model_class.object_id.to_s(16)}"
                   else
                     "#{class_name}@0x#{model_class.object_id.to_s(16)}"
                   end
        :"#{class_id}#{format}#{register_id}"
      end

      # Build unique key for mapping cache
      #
      # IMPORTANT: Always include object_id to ensure uniqueness for classes
      # with the same name. This is necessary because tests can define multiple
      # classes with identical names (e.g., both returning "Vcard").
      #
      # @param model_class [Class] The model class
      # @param format [Symbol] The format
      # @param register [Symbol, Register, nil] The register
      # @return [Symbol] Unique cache key
      def mapping_key(model_class, format, register)
        register_id = extract_register_id(register)
        # Always include object_id to prevent cache pollution between classes
        # with the same name (common in test fixtures)
        class_name = model_class.name
        # For anonymous classes, name is nil or empty, use object_id only
        # For named classes, include both name and object_id for uniqueness
        class_id = if class_name.nil? || class_name.empty?
                     "0x#{model_class.object_id.to_s(16)}"
                   else
                     "#{class_name}@0x#{model_class.object_id.to_s(16)}"
                   end
        :"#{class_id}#{format}#{register_id}"
      end

      # Extract register ID from register parameter
      #
      # @param register [Symbol, Register, nil] The register
      # @return [Symbol] The register ID
      def extract_register_id(register)
        if register
          register.is_a?(Lutaml::Model::Register) ? register.id : register
        else
          Lutaml::Model::Config.default_register
        end
      end

      # Build transformation instance for format using registered builder.
      #
      # Uses the Builder Pattern (Open/Closed Principle):
      # - Built-in formats use pre-registered builders
      # - Custom formats can be added via register_builder
      # - No case statement to modify when adding new formats
      #
      # @param model_class [Class] The model class
      # @param mapping [Mapping] The resolved mapping
      # @param format [Symbol] The format
      # @param register [Symbol, Register, nil] The register
      # @return [Transformation, Mapping] The transformation instance or mapping
      def build_transformation(model_class, mapping, format, register)
        # Resolve register to instance
        register_instance = resolve_register(register)

        # Look up the builder for this format
        builder = self.class.builder_for(format)

        if builder
          # Use builder to create transformation (Open/Closed)
          builder.build(model_class, mapping, format, register_instance)
        else
          # No builder registered - return mapping directly (backward compat)
          mapping
        end
      end

      # Resolve register parameter to register ID (symbol)
      #
      # @param register [Symbol, Register, nil] The register parameter
      # @return [Symbol] The register ID
      def resolve_register(register)
        if register
          if register.is_a?(Lutaml::Model::Register)
            register.id
          else
            register
          end
        else
          Lutaml::Model::Config.default_register
        end
      end
    end
  end
end
