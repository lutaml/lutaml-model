module Lutaml
  module Model
    class Choice
      attr_reader :attributes,
                  :model,
                  :min,
                  :max

      def initialize(model, min, max)
        @attributes = []
        @model = model
        @min = min
        @max = max

        raise Lutaml::Model::InvalidChoiceRangeError.new(@min, @max) if @min.negative? || @max.negative?
      end

      def attribute(name, type, options = {})
        options[:choice] = self
        @attributes << @model.attribute(name, type, options)
      end

      def choice(min: 1, max: 1, &block)
        @attributes << Choice.new(@model, min, max).tap do |c|
          c.instance_eval(&block)
        end
      end

      def import_model_attributes(imported_model)
        imported_model.attributes.each_value do |attr|
          @model.initialize_attribute_accessor(attr)
        end

        @attributes.concat(imported_model.choice_attributes)
        @model.attributes.merge!(imported_model.attributes)
      end

      def validate_content!(object)
        validated_attributes = []
        valid = valid_attributes(object, validated_attributes)

        raise Lutaml::Model::ChoiceUpperBoundError.new(validated_attributes, @max) if valid.count > @max
        raise Lutaml::Model::ChoiceLowerBoundError.new(validated_attributes, @min) if valid.count < @min
      end

      private

      def valid_attributes(object, validated_attributes)
        @attributes.each do |attribute|
          if attribute.is_a?(Choice)
            begin
              attribute.validate_content!(object)
              validated_attributes << attribute
            rescue Lutaml::Model::ChoiceLowerBoundError
            end
          elsif Utils.present?(object.public_send(attribute.name))
            validated_attributes << attribute.name
          end
        end

        validated_attributes
      end
    end
  end
end
