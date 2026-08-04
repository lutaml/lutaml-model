# frozen_string_literal: true

module Lutaml
  module Model
    module Validation
      # Models being validated on this thread's current stack.
      VALIDATING_KEY = :lutaml_model_validating

      # Whether a model is already being validated further up this stack.
      def self.visiting?(model)
        stack = Thread.current[VALIDATING_KEY]
        !stack.nil? && stack.key?(model)
      end

      # The single guarded entry point. A model can appear inside its own
      # subtree, and re-entering it would recurse forever, so a re-entry
      # returns early — the outer call is already collecting its errors.
      #
      # Override #collect_validation_errors, not this method, to add
      # validation that must run inside the cycle guard. Overriding #validate
      # directly puts the override outside the guard.
      def validate(register: Lutaml::Model::Config.default_register)
        visiting = (Thread.current[VALIDATING_KEY] ||= {}.compare_by_identity)
        return [] if visiting.key?(self)

        begin
          # Marked inside the begin, so an exception delivered between the
          # check and the mark cannot strand an entry on the stack.
          visiting[self] = true
          collect_validation_errors(register)
        ensure
          visiting.delete(self)
          Thread.current[VALIDATING_KEY] = nil if visiting.empty?
        end
      end

      def collect_validation_errors(register)
        errors = []

        self.class.attributes(register).each do |name, attr|
          value = public_send(:"#{name}")

          begin
            # Recurse into nested models — a single child or every element of
            # an array — so their own validation errors surface here. A
            # Collection is itself a model, so it is validated as one: that
            # runs its collection-level rules as well as its elements.
            # #validate takes no arguments here: it is a public override point
            # that downstream models legitimately define with zero arity.
            (value.is_a?(::Array) ? value : [value]).each do |item|
              next unless item.is_a?(Lutaml::Model::Serialize)
              # Skip a model already on the stack rather than calling into it.
              # A downstream #validate override sits above the guard, so
              # re-entering it would run the override's own body a second time.
              next if Validation.visiting?(item)

              sub_errors = item.validate
              errors.concat(sub_errors) if sub_errors.is_a?(Array)
            end

            # Always run attribute-level validation (cardinality, required,
            # enum, pattern, polymorphic, custom) regardless of value type.
            attr.validate_value!(value, register, instance_object: self)
          rescue Lutaml::Model::CollectionCountOutOfRangeError => e
            errors << e unless attr.choice
          rescue Lutaml::Model::InvalidValueError,
                 Lutaml::Model::CollectionTrueMissingError,
                 Lutaml::Model::PolymorphicError,
                 Lutaml::Model::ValidationFailedError,
                 Lutaml::Model::RequiredAttributeMissingError,
                 Lutaml::Model::PatternNotMatchedError => e
            errors << e
          end
        end

        validate_helper(errors, register)
      end

      def validate!(register: Lutaml::Model::Config.default_register)
        errors = validate(register: register)
        raise Lutaml::Model::ValidationError.new(errors) if errors.any?
      end

      def validate_helper(errors, register)
        self.class.choice_attributes.each do |attribute|
          attribute.validate_content!(self, register)
        end

        validate_sequence!(errors, order_names, register)
        errors
      rescue Lutaml::Model::ChoiceUpperBoundError,
             Lutaml::Model::ChoiceLowerBoundError => e
        errors << e
      end

      def validate_sequence!(errors, names, register)
        sequences = format_element_sequences(register)
        return errors if names.empty? || sequences.nil?

        sequences.each do |sequence|
          sequence.validate_content!(names, self, register)
        end
        errors
      rescue Lutaml::Model::IncorrectSequenceError,
             Lutaml::Model::ChoiceUpperBoundError,
             Lutaml::Model::ChoiceLowerBoundError => e
        errors << e
      end

      # Hook for getting format-specific element sequences for validation.
      # XML overrides via InstanceMethods prepend.
      #
      # @param _register [Symbol, nil] The register context
      # @return [Array, nil] Element sequences or nil
      def format_element_sequences(_register)
        nil
      end

      # Default: no element order. XML overrides via InstanceMethods prepend
      # with attr_accessor :element_order.
      def element_order
        nil
      end

      def order_names
        return [] unless element_order

        element_order.each_with_object([]) do |element, arr|
          next if element.text?

          arr << element.name
        end
      end
    end
  end
end
