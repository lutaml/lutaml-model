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

      def validate_content!(element_order, model_class)
        defined_order = extract_defined_order(model_class.attributes)
        validate_sequence!(
          defined_order,
          element_order_index(element_order, defined_order),
          element_order,
        )
      end

      private

      def validate_sequence!(defined_order, eo_index, element_order)
        choices = ::Hash.new(0)
        defined_order.each do |element, klass_attr|
          updated_index = if klass_attr.collection?
                            attr_collection(element_order, eo_index, element, klass_attr, choices)
                          elsif klass_attr.choice
                              klass_attr.choiced_appearance_count(element_order, eo_index, choices).to_i
                          end

          next eo_index = updated_index if updated_index
          next eo_index += 1 if element_order[eo_index] == element

          raise IncorrectSequenceError.new(element, element_order[eo_index])
        end
        choices.each { |choice, count| choice.validate_count_in_sequence!(count) }
      end

      def attr_collection(element_order, current_index, element, klass_attr, choices)
        if add_missing_element?(element_order, current_index, element, klass_attr)
          element_order.insert(current_index, element)
          nil
        else
          klass_attr.sequenced_appearance_count(
            element_order,
            element,
            current_index,
            choices,
          )
        end
      end

      def add_missing_element?(element_order, eo_index, element, klass_attr)
        return false unless klass_attr.collection_range.min.zero?

        element_order[eo_index] != element && !element_order.include?(element)
      end

      def element_order_index(element_order, defined_order)
        element_order.find_index { |d| defined_order.key?(d) } || 0
      end

      def extract_defined_order(model_attrs)
        @attributes.each_with_object({}) do |rule, acc|
          acc[rule.name.to_s] = model_attrs[rule.to.to_s] ||
            model_attrs[rule.to.to_sym]
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
