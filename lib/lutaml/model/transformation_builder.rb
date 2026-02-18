# frozen_string_literal: true

module Lutaml
  module Model
    # Abstract base class for transformation builders.
    #
    # Implements the Builder Pattern for creating format-specific transformations.
    # This satisfies the Open/Closed Principle: open for extension, closed for
    # modification.
    #
    # To add a new serialization format:
    # 1. Create a subclass of TransformationBuilder
    # 2. Implement the `build` class method
    # 3. Register with TransformationRegistry.register_builder(format, builder)
    #
    # @example Creating a custom builder
    #   class ProtobufTransformationBuilder < TransformationBuilder
    #     def self.build(model_class, mapping, format, register)
    #       Protobuf::Transformation.new(model_class, mapping, format, register)
    #     end
    #   end
    #
    #   TransformationRegistry.register_builder(:protobuf, ProtobufTransformationBuilder)
    #
    # @abstract Subclasses must implement {build}
    class TransformationBuilder
      # Build a transformation instance for the given format.
      #
      # @abstract Subclasses must implement this method
      # @param model_class [Class] The model class
      # @param mapping [Mapping] The resolved mapping
      # @param format [Symbol] The format symbol
      # @param register [Register, nil] The register for type resolution
      # @return [Transformation] The transformation instance
      # @raise [NotImplementedError] if not implemented by subclass
      def self.build(model_class, mapping, format, register)
        raise NotImplementedError,
              "#{self.class}.build must be implemented"
      end

      # Check if this builder can handle the given format.
      #
      # Default implementation checks the FORMATS constant.
      # Subclasses can override for more complex logic.
      #
      # @param format [Symbol] The format to check
      # @return [Boolean] true if this builder handles the format
      def self.handles?(format)
        return false unless const_defined?(:FORMATS, false)

        const_get(:FORMATS, false).include?(format)
      end
    end
  end
end
