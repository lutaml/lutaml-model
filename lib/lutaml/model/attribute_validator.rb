# frozen_string_literal: true

module Lutaml
  module Model
    # Handles validation logic for Lutaml::Model::Attribute.
    #
    # Extracted from Attribute class to provide focused validation
    # concerns and better separation of responsibilities.
    class AttributeValidator
      # @return [Attribute] The attribute being validated
      attr_reader :attribute

      # Initialize a new validator for an attribute
      #
      # @param attribute [Attribute] The attribute to validate
      def initialize(attribute)
        @attribute = attribute
      end

      # Validate a value for the attribute
      #
      # Performs all validation checks including:
      # - Required value validation
      # - Enum value validation
      # - Collection range validation
      # - Pattern validation
      # - Polymorphic type validation
      # - Custom validations
      #
      # @param value [Object] The value to validate
      # @param register [Symbol, Register, nil] The register for type resolution
      # @return [true] if validation passes
      # @raise [InvalidValueError] if value is not in allowed values
      # @raise [CollectionCountOutOfRangeError] if collection count is out of range
      # @raise [PatternNotMatchedError] if pattern doesn't match
      # @raise [PolymorphicError] if polymorphic type is invalid
      # @raise [ValidationFailedError] if custom validations fail
      def validate!(value, register)
        ensure_required?(value)

        value = attribute.default(register) if value.nil?
        resolved_type = attribute.type(register)

        valid_value?(value) &&
          valid_collection?(value, attribute) &&
          valid_pattern?(value, resolved_type) &&
          validate_polymorphic!(value, resolved_type) &&
          execute_validations!(value)
      end

      # Validate that required attributes have values
      #
      # @param value [Object] The value to check
      # @return [true] if validation passes
      # @raise [RequiredAttributeMissingError] if required value is missing
      def ensure_required?(value)
        return true unless attribute.options[:required]
        return false if value.nil?
        return false if value.respond_to?(:empty?) && value.empty?

        true
      end

      # Check if value is in the allowed enum values
      #
      # @param value [Object] The value to check
      # @return [true] if value is valid or not an enum
      # @raise [InvalidValueError] if value is not in allowed values
      def valid_value?(value)
        return true if value.nil? && attribute.singular?
        return true unless attribute.enum?
        return true if Utils.uninitialized?(value)

        unless valid_value_check?(value)
          raise Lutaml::Model::InvalidValueError.new(
            attribute.name,
            value,
            attribute.enum_values,
          )
        end

        true
      end

      # Check if value matches the pattern (for String types)
      #
      # @param value [Object] The value to check
      # @param resolved_type [Class] The resolved type
      # @return [true] if value matches pattern or pattern not applicable
      # @raise [PatternNotMatchedError] if pattern doesn't match
      def valid_pattern?(value, resolved_type)
        return true unless resolved_type == Lutaml::Model::Type::String
        return true unless attribute.pattern

        unless attribute.pattern.match?(value)
          raise Lutaml::Model::PatternNotMatchedError.new(
            attribute.name,
            attribute.pattern,
            value,
          )
        end

        true
      end

      # Validate collection count is within range
      #
      # @param value [Object] The value to check
      # @param caller [Object] The calling context (usually the attribute)
      # @return [true] if validation passes
      # @raise [CollectionTrueMissingError] if collection value without collection: true
      # @raise [CollectionCountOutOfRangeError] if count is out of range
      def valid_collection?(value, caller)
        if attribute.collection_instance?(value) && !attribute.collection?
          raise Lutaml::Model::CollectionTrueMissingError.new(
            attribute.name,
            caller,
          )
        end

        return true unless attribute.collection?

        # Allow any value for unbounded collections
        return true if attribute.collection == true

        unless (Utils.uninitialized?(value) && attribute.resolved_collection.min.zero?) ||
            attribute.collection_instance?(value)
          raise Lutaml::Model::CollectionCountOutOfRangeError.new(
            attribute.name,
            value,
            attribute.collection,
          )
        end

        return true unless attribute.resolved_collection.is_a?(Range)

        valid_collection_count?(value)
      end

      # Validate polymorphic type
      #
      # @param value [Object] The value to check
      # @param resolved_type [Class] The resolved type
      # @return [true] if validation passes
      # @raise [PolymorphicError] if polymorphic type is invalid
      def validate_polymorphic!(value, resolved_type)
        return true if validate_polymorphic(value, resolved_type)

        raise Lutaml::Model::PolymorphicError.new(value, attribute.options, resolved_type)
      end

      # Validate collection range configuration
      #
      # @return [void]
      # @raise [ArgumentError] if collection range is invalid
      def validate_collection_range!
        range = attribute.options[:collection]
        return if range == true
        return if attribute.custom_collection?

        unless range.is_a?(Range)
          raise ArgumentError, "Invalid collection range: #{range}"
        end

        validate_range!(range)
      end

      private

      # Check if value is in allowed enum values
      #
      # @param value [Object] The value to check
      # @return [Boolean] true if value is valid
      def valid_value_check?(value)
        return true unless attribute.options[:values]

        attribute.options[:values].include?(value)
      end

      # Validate polymorphic type (non-raising version)
      #
      # @param value [Object] The value to check
      # @param resolved_type [Class] The resolved type
      # @return [Boolean] true if valid polymorphic type
      def validate_polymorphic(value, resolved_type)
        if value.is_a?(Array)
          return value.all? do |v|
            validate_polymorphic(v, resolved_type)
          end
        end
        return true unless attribute.options[:polymorphic]

        valid_polymorphic_type?(value, resolved_type)
      end

      # Check if value is a valid polymorphic type
      #
      # @param value [Object] The value to check
      # @param resolved_type [Class] The resolved type
      # @return [Boolean] true if valid
      def valid_polymorphic_type?(value, resolved_type)
        return value.is_a?(resolved_type) unless has_polymorphic_list?

        attribute.options[:polymorphic].include?(value.class) &&
          value.is_a?(resolved_type)
      end

      # Check if polymorphic list is defined
      #
      # @return [Boolean] true if polymorphic list exists
      def has_polymorphic_list?
        attribute.options[:polymorphic]&.is_a?(Array)
      end

      # Validate collection count within range
      #
      # @param value [Object] The collection value
      # @return [true] if count is valid
      # @raise [CollectionCountOutOfRangeError] if count is out of range
      def valid_collection_count?(value)
        collection = attribute.resolved_collection

        if collection.is_a?(Range) && collection.end.infinite?
          if value.size < collection.begin
            raise Lutaml::Model::CollectionCountOutOfRangeError.new(
              attribute.name,
              value,
              attribute.collection,
            )
          end
        elsif collection.is_a?(Range) && !collection.cover?(value.size)
          raise Lutaml::Model::CollectionCountOutOfRangeError.new(
            attribute.name,
            value,
            attribute.collection,
          )
        end

        true
      end

      # Validate a range object
      #
      # @param range [Range] The range to validate
      # @return [void]
      # @raise [ArgumentError] if range is invalid
      def validate_range!(range)
        if range.begin.nil?
          raise ArgumentError,
                "Invalid collection range: #{range}. Begin must be specified."
        end

        if range.begin.negative?
          raise ArgumentError,
                "Invalid collection range: #{range}. " \
                "Begin must be non-negative."
        end

        if range.end && range.end < range.begin
          raise ArgumentError,
                "Invalid collection range: #{range}. " \
                "End must be greater than or equal to begin."
        end
      end

      # Execute custom validations on the attribute value
      #
      # @param value [Object] The value to validate
      # @return [true] if all validations pass
      # @raise [ValidationFailedError] if any validation fails
      def execute_validations!(value)
        return true if Utils.blank?(value)

        memoization_container = {}
        errors = Lutaml::Model::Validator.call(
          value,
          attribute.validations,
          memoization_container,
        )

        return true if errors.empty?

        raise Lutaml::Model::ValidationFailedError.new(errors)
      end
    end
  end
end
