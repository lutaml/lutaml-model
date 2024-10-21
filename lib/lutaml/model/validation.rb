module Lutaml
  module Model
    module Validation
      def validate
        errors = []
        self.class.attributes.each do |name, attr|
          value = public_send(:"#{name}")
          begin
            if value.respond_to?(:validate!)
              value.validate!
            else
              attr.validate_value!(value)
            end
          rescue Lutaml::Model::InvalidValueError,
                 Lutaml::Model::CollectionCountOutOfRangeError,
                 PatternNotMatchedError => e
            errors << e
          end
        end

        validate_helper(errors)
      end

      def validate!
        errors = validate
        raise Lutaml::Model::ValidationError.new(errors) if errors.any?
      end

      def validate_helper(errors)
        self.class.choice_attributes.each { |attribute| attribute.validate_content!(self) }
        errors
      rescue Lutaml::Model::ChoiceUpperBoundError,
             Lutaml::Model::ChoiceLowerBoundError => e
        errors << e
      end
    end
  end
end
