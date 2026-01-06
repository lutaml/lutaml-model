module Lutaml
  module Model
    module Validation
      def validate(register: Lutaml::Model::Config.default_register)
        errors = []

        self.class.attributes(register).each do |name, attr|
          value = public_send(:"#{name}")

          begin
            if value.respond_to?(:validate)
              errors.concat(value.validate)
            else
              attr.validate_value!(value, register)
            end
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
        sequences = self.class.mappings_for(:xml, register)&.element_sequence
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
