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

        errors.concat(validate_helper)
      end

      def validate!
        errors = validate
        raise Lutaml::Model::ValidationError.new(errors) if errors.any?
      end

      def validate_helper
        errors = []

        begin
          self.class.attribute_tree.each { |attribute| attribute.validate_content!(self) }
          errors
        rescue Lutaml::Model::InvalidChoiceError,
               Lutaml::Model::InvalidSequenceError => e
          errors << e
        end
      end
    end
  end
end
