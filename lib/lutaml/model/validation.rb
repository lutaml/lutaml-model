module Lutaml
  module Model
    module Validation
      def validate
        errors = []

        self.class.attributes.each do |name, attr|
          value = instance_variable_get(:"@#{name}")
          begin
            attr.validate_value!(value)
          rescue Lutaml::Model::InvalidValueError,
                 Lutaml::Model::CollectionCountOutOfRangeError,
                 PatternNotMatchedError => e
            errors << e
          end
        end

        begin
          self.class.attribute_tree.each { |attribute| attribute.validate_count!(self) }
        rescue Lutaml::Model::InvalidChoiceError => e
          errors << e
        end

        errors
      end

      def validate!
        errors = validate
        raise Lutaml::Model::ValidationError.new(errors) if errors.any?
      end
    end
  end
end
