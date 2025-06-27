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

      def map_element(
        name,
        to: nil,
        render_nil: false,
        render_default: false,
        with: {},
        delegate: nil,
        cdata: false,
        namespace: (namespace_set = false
                    nil),
        prefix: (prefix_set = false
                 nil),
        transform: {}
      )
        args = {
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
          cdata: cdata,
          transform: transform,
        }
        args[:namespace] = namespace if namespace_set.nil?
        args[:prefix] = prefix if prefix_set.nil?

        @attributes << @model.map_element(
          name,
          **args,
        )
      end

      def import_model_mappings(model)
        return import_mappings_later(model) if model_importable?(model)
        raise Lutaml::Model::ImportModelWithRootError.new(model) if model.root?

        @model.import_model_mappings(model)
        @attributes.concat(model.mappings_for(:xml).elements)
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

      def validate_content!(element_order, klass)
        defined_order = extract_defined_order(klass)
        validate_sequence!(defined_order, element_order)
      end

      private

      def validate_sequence!(defined_order, element_order)
        eo_index = element_order.index(defined_order&.keys&.first) || 0

        defined_order.each do |element, klass_attr|
          element_exist = Proc.new { element_order[eo_index] == element }

          if klass_attr.collection?
            min, max = klass_attr.min_max_range
            count = []
            while eo_index < element_order.size && element_exist.call && count.size < max
              count << element_order[eo_index]
              eo_index += 1
            end
            if count.size < min || count.size > max
              raise Lutaml::Model::CollectionCountOutOfRangeError.new(element, count, klass_attr.collection_range)
            end
            next
          elsif element_exist.call
            next eo_index += 1
          end
          raise Lutaml::Model::IncorrectSequenceError.new(element, element_order[eo_index])
        end
      end

      def extract_defined_order(klass)
        @attributes.each_with_object({}) do |rule, acc|
          acc[rule.name.to_s] = klass.attributes[rule.to.to_s] ||
            klass.attributes[rule.to.to_sym]
        end
      end

      def model_importable?(model)
        model.is_a?(Symbol) ||
          model.is_a?(String)
      end

      def import_mappings_later(model)
        @model.sequence_importable_mappings[self] << model.to_sym
        @model.mappings_imported = false
      end
    end
  end
end
