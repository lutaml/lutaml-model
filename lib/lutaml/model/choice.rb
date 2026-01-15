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

      def validate_sequence_content!(elements, appearance_count = 0)
        choices_hash = ::Hash.new { |h, k| h[k] = 0 }
        choices_hash[self] = appearance_count
        current_index = validate_choices(elements, choices_hash)
        raise_errors(choices_hash)
        current_index
      end

      def validate_content!(object)
        validated_attributes = []
        valid = valid_attributes(object, validated_attributes)

        # Allow empty choice if it can render empty elements
        if valid.count.zero? && can_render_empty?(object)
          return
        end

        validate_count_errors!(valid.count, validated_attributes)
      end

      def can_render_empty?(object)
        # Check if ALL attributes in the choice have render_empty: true
        # This allows empty instances of required elements to pass validation
        mapping = @model.mappings_for(:xml)
        return false unless mapping&.elements

        @attributes.all? do |attribute|
          next true if attribute.is_a?(Choice)  # Nested choices handled separately

          rule = mapping.elements.find { |r| r.to == attribute.name }
          rule&.render_empty?
        end
      rescue StandardError
        false
      end

      def import_model_attributes(model, register = nil)
        if later_importable?(model)
          return import_model_later(model,
                                    :import_model_attributes)
        end

        root_model_error(model, register)
        imported_attributes = Utils.deep_dup(model.attributes(register).values)
        imported_attributes.each do |attr|
          attr.options[:choice] = self
          @model.define_attribute_methods(attr, register)
        end
        @attributes.concat(imported_attributes)
        attrs_hash = imported_attributes.to_h { |attr| [attr.name, attr] }
        @model.attributes(register).merge!(attrs_hash)
      end

      def deep_duplicate(new_model)
        choice = self.class.new(new_model, @min, @max)
        @attributes.map do |attr|
          choice.attributes << if attr.is_a?(Choice)
                                 attr.deep_duplicate(new_model)
                               else
                                 choice_attr = new_model.instance_variable_get(:@attributes)[attr.name]
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

      def validate_choices(elements, choices_hash)
        eo_index = 0
        filtered = extract_choice_defined_names
        appeared_elements = elements
          .take_while { |d| filtered.key?(d) }
          .slice_when { |prev, curr| prev != curr }
        appeared_elements.each do |element|
          eo_index += element.count
          choice_attr = flat_attributes.find do |attr|
            attr.name == filtered[element.first]
          end
          choices_hash[self] += choice_appearances(choices_hash, choice_attr,
                                                   element)
        end
        eo_index
      end

      def choice_appearances(choices_hash, choice_attr, element)
        if choice_attr.choice == self
          choice_attr.validate_choice_content!(element)
        else
          choices_hash[choice_attr.choice] += choice_attr.choice.validate_sequence_content!(
            element,
            choices_hash[choice_attr.choice],
          )
          1
        end
      end

      def extract_choice_defined_names
        mapping_elements = @model.mappings_for(:xml).elements
        attribute_names  = flat_attributes.to_h do |attr|
          [attr.name.to_sym, attr]
        end
        name_with_to = mapping_elements.to_h do |element|
          [element.name.to_s, element.to]
        end
        name_with_to.select { |_, to| attribute_names.key?(to) }
      end

      def root_model_error(model, register = nil)
        return unless model.root?(register)

        raise Lutaml::Model::ImportModelWithRootError.new(model)
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
            validate_attribute_content!(object, attribute, validated_attributes)
          elsif should_render_empty?(object, attribute)
            # Empty value but should render (e.g., required element with render_empty)
            validated_attributes << attribute.name
          end
        end

        validated_attributes
      end

      def should_render_empty?(object, attribute)
        value = object.public_send(attribute.name)
        return false if Utils.uninitialized?(value)
        return false unless Utils.empty?(value) || (value.respond_to?(:empty?) && value.empty?)

        # Check if this attribute should render when empty
        mapping = @model.mappings_for(:xml)
        return false unless mapping&.elements

        # Search through all elements (including imported ones after resolution)
        rule = mapping.elements.find { |r| r.to == attribute.name }
        return false unless rule

        # Check if rule has render_empty option set
        rule.render_empty?
      rescue StandardError
        # If anything fails, default to false (don't render)
        false
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
        @model.instance_variable_set(:@choices_imported, false)
        @model.setup_trace_point
      end
    end
  end
end
