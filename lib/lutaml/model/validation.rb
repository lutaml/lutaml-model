module Lutaml
  module Model
    module Validation
      def validate
        errors = []
        self.class.attributes.each do |name, attr|
          value = self.public_send(:"#{name}")
          begin
            attr.validate_value!(value)
          rescue Lutaml::Model::InvalidValueError,
                 Lutaml::Model::CollectionCountOutOfRangeError,
                 PatternNotMatchedError => e
            errors << e
          end
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
