module Lutaml
  module Model
    module Validation
      def validate(register: Lutaml::Model::Config.default_register)
        errors = []
        self.class.attributes.each do |name, attr|
          value = public_send(:"#{name}")
          begin
            if value.respond_to?(:validate)
              errors.concat(value.validate)
            else
              attr.validate_value!(value, register)
            end
          rescue Lutaml::Model::InvalidValueError,
                 Lutaml::Model::CollectionCountOutOfRangeError,
                 Lutaml::Model::CollectionTrueMissingError,
                 Lutaml::Model::PolymorphicError,
                 PatternNotMatchedError => e
            errors << e
          end
        end

        validate_helper(errors)
      end

      def validate!(register: Lutaml::Model::Config.default_register)
        errors = validate(register: register)
        raise Lutaml::Model::ValidationError.new(errors) if errors.any?
      end

      def validate_helper(errors)
        self.class.choice_attributes.each do |attribute|
          attribute.validate_content!(self)
        end
        errors
      rescue Lutaml::Model::ChoiceUpperBoundError,
             Lutaml::Model::ChoiceLowerBoundError => e
        errors << e
      end
    end
  end
end
