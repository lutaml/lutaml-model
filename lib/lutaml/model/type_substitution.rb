# frozen_string_literal: true

module Lutaml
  module Model
    # TypeSubstitution represents a single type substitution rule.
    #
    # This is an INTERNAL class. Users should use Register and GlobalRegister.
    #
    # Responsibility: Represent an immutable type substitution
    #   (from_type => to_type)
    #
    # This is a Value Object:
    # - Immutable after creation
    # - Equality based on from_type and to_type
    # - NO knowledge of where substitutions are stored
    # - NO knowledge of substitution chains
    #
    # @api private
    #
    # @example Basic usage
    #   sub = TypeSubstitution.new(
    #     from_type: CustomText,
    #     to_type: Lutaml::Model::Type::String
    #   )
    #   sub.applies_to?(CustomText) #=> true
    #   sub.apply(CustomText) #=> Lutaml::Model::Type::String
    #   sub.apply(OtherClass) #=> nil
    #
    class TypeSubstitution
      # @return [Class] The type to substitute from
      attr_reader :from_type

      # @return [Class] The type to substitute to
      attr_reader :to_type

      # Create a new type substitution rule
      #
      # @param from_type [Class] The type to be substituted
      # @param to_type [Class] The type to substitute with
      #
      # @example
      #   sub = TypeSubstitution.new(
      #     from_type: MyCustomText,
      #     to_type: Lutaml::Model::Type::String
      #   )
      def initialize(from_type:, to_type:)
        @from_type = from_type
        @to_type = to_type
        freeze
      end

      # Check if this substitution applies to the given class
      #
      # @param klass [Class] The class to check
      # @return [Boolean] true if this substitution applies
      #
      # @example
      #   sub.applies_to?(CustomText) #=> true
      #   sub.applies_to?(OtherClass) #=> false
      def applies_to?(klass)
        klass == from_type
      end

      # Apply this substitution to a class
      #
      # @param klass [Class] The class to potentially substitute
      # @return [Class, nil] The substituted type if applies, nil otherwise
      #
      # @example
      #   sub.apply(CustomText) #=> Lutaml::Model::Type::String
      #   sub.apply(OtherClass) #=> nil
      def apply(klass)
        applies_to?(klass) ? to_type : nil
      end

      # Value object equality
      #
      # Two TypeSubstitutions are equal if they have the same
      # from_type and to_type
      #
      # @param other [Object] The object to compare
      # @return [Boolean] true if equal
      def ==(other)
        return false unless other.is_a?(TypeSubstitution)

        from_type == other.from_type && to_type == other.to_type
      end

      alias eql? ==

      # Hash code for use as hash key
      #
      # @return [Integer] Hash code
      def hash
        [from_type, to_type].hash
      end

      # Human-readable representation
      #
      # @return [String] String representation
      def to_s
        "#<#{self.class.name} #{from_type} => #{to_type}>"
      end

      alias inspect to_s

      # Create a copy with potentially different values
      #
      # @param from_type [Class] Optional new from_type (defaults to current)
      # @param to_type [Class] Optional new to_type (defaults to current)
      # @return [TypeSubstitution] New substitution
      def with(from_type: self.from_type, to_type: self.to_type)
        self.class.new(from_type: from_type, to_type: to_type)
      end
    end
  end
end
