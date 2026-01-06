module Lutaml
  module Model
    class Choice
      attr_reader :attributes,
                  :model,
                  :min,
                  :max

      INTERNAL_ATTRIBUTES = %i[@flat_attributes].freeze

      def initialize(model, min, max)
        @attributes = []
        @model = model
        @min = min
        @max = max

        if @min.negative? || @max.negative?
          raise Lutaml::Model::InvalidChoiceRangeError.new(@min,
                                                           @max)
        end
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

      def flat_attributes
        @flat_attributes ||= @attributes.flat_map do |attribute|
          attribute.is_a?(Choice) ? attribute.flat_attributes : attribute
        end
      end

      def validate_sequence_content!(elements, appearance_count = 0, register = nil)
        choices_hash = ::Hash.new { |h, k| h[k] = 0 }
        choices_hash[self] = appearance_count
        current_index = validate_choices(elements, choices_hash, register)
        raise_errors(choices_hash)
        current_index
      end

      def validate_content!(object, register = nil)
        validated_attributes = []
        valid = valid_attributes(object, validated_attributes, register)
        validate_count_errors!(valid.count, validated_attributes)
      end

      def __import_model_attributes(model, register_id = nil)
        return import_model_attributes(model) if register_id == :default

        current_record = @model.instance_variable_get(:@__register_record)[register_id]
        imported_attributes = Utils.deep_dup(model.attributes(register_id))
        imported_attributes.each_value do |attr|
          attr.options[:choice] = self
        end
        current_record[:attributes].merge!(imported_attributes)
      end

      def import_model_attributes(model)
        if later_importable?(model)
          return import_model_later(model,
                                    :__import_model_attributes)
        end

        root_model_error(model)
        imported_attributes = Utils.deep_dup(model.attributes.values)
        imported_attributes.each do |attr|
          attr.options[:choice] = self
          @model.define_attribute_methods(attr)
        end
        @attributes.concat(imported_attributes)
        attrs_hash = imported_attributes.to_h { |attr| [attr.name, attr] }
        @model.attributes.merge!(attrs_hash)
      end

      def deep_duplicate(new_model, register = nil)
        choice = self.class.new(new_model, @min, @max)
        @attributes.map do |attr|
          choice.attributes << if attr.is_a?(Choice)
                                 attr.deep_duplicate(new_model, register)
                               else
                                 choice_attr = new_model.attributes(register)[attr.name]
                                 next if choice_attr.nil?

                                 choice_attr.options[:choice] = choice
                                 choice_attr
                               end
        end
        choice
      end

      def validate_count_errors!(count, attributes)
        return if count.between?(@min, @max)
        return if optional_empty_choice?(count)

        if count < @min
          raise Lutaml::Model::ChoiceLowerBoundError.new(attributes,
                                                         @min)
        end
        if count > @max
          raise Lutaml::Model::ChoiceUpperBoundError.new(attributes,
                                                         @max)
        end
      end

      def optional_empty_choice?(count)
        count.zero? && @attributes.any? do |attr|
          next attr.optional_empty_choice?(count) if attr.is_a?(self.class)

          optional_attribute?(attr)
        end
      end

      def pretty_print_instance_variables
        (instance_variables - INTERNAL_ATTRIBUTES).sort
      end

      private

      def raise_errors(choices_hash)
        flat_attr_names = flat_attributes.map { |attr| attr.name.to_s }
        choices_hash.each do |choice_attr, count|
          next if choices_hash[choice_attr].between?(choice_attr.min,
                                                     choice_attr.max)

          if count < choice_attr.min
            raise Lutaml::Model::ChoiceLowerBoundError.new(flat_attr_names,
                                                           choice_attr.min)
          end
          if count > choice_attr.max
            raise Lutaml::Model::ChoiceUpperBoundError.new(flat_attr_names,
                                                           choice_attr.max)
          end
        end
      end

      def validate_choices(elements, choices_hash, register = nil)
        eo_index = 0
        filtered = extract_choice_defined_names(register)
        appeared_elements = elements
          .take_while { |d| filtered.key?(d) }
          .slice_when { |prev, curr| prev != curr }
        appeared_elements.each do |element|
          eo_index += element.count
          choice_attr = flat_attributes.find do |attr|
            attr.name == filtered[element.first]
          end
          choices_hash[self] += choice_appearances(choices_hash, choice_attr,
                                                   element, register)
        end
        eo_index
      end

      def choice_appearances(choices_hash, choice_attr, element, register = nil)
        if choice_attr.choice == self
          choice_attr.validate_choice_content!(element)
        else
          choices_hash[choice_attr.choice] += choice_attr.choice.validate_sequence_content!(
            element,
            choices_hash[choice_attr.choice],
            register,
          )
          1
        end
      end

      def extract_choice_defined_names(register = nil)
        mapping_elements = @model.mappings_for(:xml, register).elements(register)
        attribute_names  = flat_attributes.to_h do |attr|
          [attr.name.to_sym, attr]
        end
        name_with_to = mapping_elements.to_h do |element|
          [element.name.to_s, element.to]
        end
        name_with_to.select { |_, to| attribute_names.key?(to) }
      end

      def root_model_error(model)
        return unless model.root?(nil)

        raise Lutaml::Model::ImportModelWithRootError.new(model)
      end

      def valid_attributes(object, validated_attributes, register = nil)
        @attributes.each do |attribute|
          if attribute.is_a?(Choice)
            begin
              attribute.validate_content!(object, register)
              validated_attributes << attribute
            rescue Lutaml::Model::ChoiceLowerBoundError
            end
          elsif Utils.present?(object.public_send(attribute.name))
            validate_attribute_content!(object, attribute, validated_attributes)
          end
        end

        validated_attributes
      end

      def validate_attribute_content!(object, attribute, validated_attributes)
        range = attribute.resolved_collection
        validated_attributes << if range.nil? || range.end.nil? || range.end.infinite?
                                  attribute.name
                                else
                                  validate_count_in_range!(
                                    object.public_send(attribute.name),
                                    attribute,
                                    range,
                                  )
                                end
      end

      def validate_count_in_range!(attr_value, attribute, range)
        range_count = attr_value.each_slice(range.end).count
        validate_count_errors!(range_count, [attribute.name.to_s])

        attribute.name
      end

      def optional_attribute?(attribute)
        range = attribute.resolved_collection
        return false unless range.is_a?(Range)

        range.begin.zero?
      end

      def later_importable?(model)
        model.is_a?(Symbol) || model.is_a?(String)
      end

      def import_model_later(model, method)
        @model.importable_choices[self][method] << model.to_sym
        @model.setup_trace_point
      end
    end
  end
end
