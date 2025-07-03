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

      def ==(other)
        @attributes == other.attributes &&
          @min == other.min &&
          @max == other.max &&
          @model == other.model
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

      def validate_content!(object)
        validated_attributes = []
        valid = valid_attributes(object, validated_attributes)

        raise Lutaml::Model::ChoiceUpperBoundError.new(validated_attributes, @max) if valid.count > @max
        raise Lutaml::Model::ChoiceLowerBoundError.new(validated_attributes, @min) if valid.count < @min
      end

      def import_model(model)
        return import_model_later(model, :import_model) if model_importable?(model)

        root_model_error(model)
        import_model_attributes(model)
      end

      def import_model_attributes(model)
        return import_model_later(model, :import_model_attributes) if model_importable?(model)

        root_model_error(model)
        imported_attributes = Utils.deep_dup(model.attributes.values)
        imported_attributes.each { |attr| attr.options[:choice] = self }
        @attributes.concat(imported_attributes)
        attrs_hash = imported_attributes.to_h { |attr| [attr.name.to_s, attr] }
        @model.attributes(skip_import: true).merge!(attrs_hash)
      end

      private

      def root_model_error(model)
        raise Lutaml::Model::ImportModelWithRootError.new(model) if model.root?
      end

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

      def model_importable?(model)
        model.is_a?(Symbol) || model.is_a?(String)
      end

      def import_model_later(model, method)
        @model.importable_choices[self][method] << model.to_sym
        @model.instance_variable_set(:@choices_imported, false)
      end
    end
  end
end
