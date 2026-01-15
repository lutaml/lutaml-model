# frozen_string_literal: true

module Lutaml
  module Model
    # Abstract base class for format-specific transformations.
    #
    # A Transformation converts a model instance into a format-specific
    # intermediate representation (like XmlElement) without triggering
    # type resolution or imports during the transformation process.
    #
    # Transformations are pre-compiled at class definition time and frozen
    # to prevent modifications. They contain all necessary information
    # (compiled rules, namespaces, etc.) for transforming instances.
    #
    # @abstract Subclasses must implement {#transform} and {#compile_rules}
    class Transformation
      # @return [Class] The model class this transformation applies to
      attr_reader :model_class

      # @return [Symbol] The format (:xml, :json, :yaml, etc.)
      attr_reader :format

      # @return [Register, nil] The register used for type resolution
      attr_reader :register

      # @return [Array<CompiledRule>] Pre-compiled transformation rules
      attr_reader :compiled_rules

      # Initialize a new transformation
      #
      # @param model_class [Class] The model class to transform
      # @param mapping_dsl [Mapping, nil] The mapping DSL to compile
      # @param format [Symbol] The format (:xml, :json, :yaml, etc.)
      # @param register [Register, nil] The register for type resolution
      def initialize(model_class, mapping_dsl, format, register)
        @model_class = model_class
        @format = format
        @register = register
        @compiled_rules = compile_rules(mapping_dsl)
        freeze
      end

      # Transform a model instance into format-specific representation
      #
      # @abstract Subclasses must implement this method
      # @param model_instance [Object] The model instance to transform
      # @param options [Hash] Format-specific options
      # @return [Object] Format-specific intermediate representation
      # @raise [NotImplementedError] if not implemented by subclass
      def transform(model_instance, options = {})
        raise NotImplementedError,
              "#{self.class}#transform must be implemented"
      end

      # Collect all namespaces used in this transformation
      #
      # This method traverses compiled rules recursively to collect
      # all namespace classes, enabling namespace declaration planning
      # without triggering type resolution.
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

      # Compile mapping DSL into pre-compiled rules
      #
      # @abstract Subclasses must implement this method
      # @param mapping_dsl [Mapping, nil] The mapping DSL to compile
      # @return [Array<CompiledRule>] Array of compiled rules
      # @raise [NotImplementedError] if not implemented by subclass
      def compile_rules(mapping_dsl)
        raise NotImplementedError,
              "#{self.class}#compile_rules must be implemented"
      end
    end
  end
end