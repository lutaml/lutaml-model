module Lutaml
  module Model
    class Sequence
      attr_accessor :model
      attr_reader :attributes

      def initialize(model)
        @attributes = []
        @model = model
      end

      def attribute(name, type, options = {})
        options[:sequence] = self
        @model.attribute(name, type, options)
      end

      def sequence(&block)
        instance_eval(&block)
      end

      def map_element(name, **kwargs)
        @attributes << @model.map_element(name, **kwargs)
      end

      def import_model_mappings(model)
        return import_mappings_later(model) if later_importable?(model)
        raise Lutaml::Model::ImportModelWithRootError.new(model) if model.root?

        @model.import_model_mappings(model)
        @attributes.concat(Utils.deep_dup(model.mappings_for(:xml).elements))
      end

      def map_attribute(*)
        raise Lutaml::Model::UnknownSequenceMappingError.new("map_attribute")
      end

      def map_content(*)
        raise Lutaml::Model::UnknownSequenceMappingError.new("map_content")
      end

      def map_all(*)
        raise Lutaml::Model::UnknownSequenceMappingError.new("map_all")
      end

      def validate_content!(element_order, instance)
        validate_sequence!(
          extract_defined_order(instance.class.attributes.transform_keys(&:to_s)),
          element_order,
        )
        validate_child_content(instance)
      end

      private

      def validate_child_content(instance)
        instance.class.attributes.each_key do |name|
          value = instance.public_send(name)
          if value.respond_to?(:validate!)
            value.validate!
          elsif value.is_a?(Array)
            value.each { |v| v.validate! if v.respond_to?(:validate!) }
          end
        end
      end

      def validate_sequence!(defined_order, element_order)
        eo_index = element_order_index(element_order, defined_order)
        choices = {}

        defined_order.each do |element, klass_attr|
          eo_index = validate_sequence(element_order, eo_index, element,
                                       klass_attr, choices)
        end
      end

      def validate_sequence(element_order, eo_index, element, klass_attr,
choices)
        if klass_attr.choice
          return process_choice(element_order, eo_index, element, klass_attr,
                                choices)
        end

        if klass_attr.collection?
          occurrences = process_collection(element_order, eo_index, element,
                                           klass_attr)
        end
        return eo_index + occurrences if occurrences&.positive?
        return eo_index + 1 if element_order[eo_index] == element

        raise_incorrect_sequence_error!(element, element_order[eo_index])
      end

      def process_choice(element_order, eo_index, element, klass_attr, choices)
        return eo_index if choices[klass_attr.choice] || element_order[eo_index] != element

        choices[klass_attr.choice] = true
        eo_index + klass_attr.choice.validate_sequence_content!(element_order[eo_index..])
      end

      def raise_incorrect_sequence_error!(expected, found)
        raise Lutaml::Model::IncorrectSequenceError.new(expected, found)
      end

      def process_collection(element_order, eo_index, element, klass_attr)
        if add_missing_element?(element_order, eo_index, element, klass_attr)
          element_order.insert(eo_index, element)
          nil
        else
          klass_attr.sequenced_appearance_count(element_order, element,
                                                eo_index)
        end
      end

      def add_missing_element?(element_order, eo_index, element, klass_attr)
        return false unless klass_attr.resolved_collection.min.zero?

        element_order[eo_index] != element && !element_order.include?(element)
      end

      def element_order_index(element_order, defined_order)
        element_order.find_index { |d| defined_order.key?(d) } || 0
      end

      def extract_defined_order(model_attrs)
        @attributes.each_with_object({}) do |rule, acc|
          acc[rule.name.to_s] = model_attrs[rule.to.to_s]
        end
      end

      def later_importable?(model)
        model.is_a?(Symbol) ||
          model.is_a?(String)
      end

      def import_mappings_later(model)
        @model.sequence_importable_mappings[self] << model.to_sym
        @model.set_mappings_imported(false)
      end
    end
  end
end
