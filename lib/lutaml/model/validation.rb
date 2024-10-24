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
                 Lutaml::Model::CollectionCountOutOfRangeError => e
            errors << e
          end
        end

        grouped_attributes = self.class.group_attributes

        if grouped_attributes
          begin
            validate_group!(grouped_attributes)
          rescue Lutaml::Model::GroupAttributeNotAllSelectedError => e
            errors << e
          end
        end

        errors
      end

      def validate!
        errors = validate
        raise Lutaml::Model::ValidationError.new(errors) if errors.any?
      end

      def validate_group!(attributes)
        attributes.each_value do |attribute|
          missing_attributes = attribute.filter_map do |attr|
            value = public_send(attr.name)

            attr.name unless value
          end

          if missing_attributes.count.positive? && missing_attributes.count < attribute.count
            raise Lutaml::Model::GroupAttributeNotAllSelectedError.new(missing_attributes.join(", "))
          end
        end
      end
    end
  end
end
