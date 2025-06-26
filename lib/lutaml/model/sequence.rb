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
          namespace: namespace,
          prefix: prefix,
          transform: transform,
        }.compact

        @attributes << @model.map_element(
          name,
          **args
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
        defined_order = @attributes.each_with_object({}) { |rule, acc| acc[rule.name.to_s] = klass.attributes[rule.to] }
        start_index = element_order.index(defined_order.first)
        collection_skippable = []

        defined_order.each.with_index(start_index) do |(element, attribute), i|
          next if element_order[i] == element
          next if attribute.collection? && attribute.collection_range.min.zero?

          raise Lutaml::Model::IncorrectSequenceError.new(element, element_order[i])
        end
      end

      private

      def collection_handling
        @attributes.each do |attribute|
          next unless attribute.collection?
          next if attribute.collection_range.min.zero?

          collection_skippable << attribute
        end
      end

      def model_importable?(model)
        model.is_a?(Symbol) || model.is_a?(String)
      end

      def import_mappings_later(model)
        @model.sequence_importable_mappings[self] << model.to_sym
        @model.mappings_imported = false
      end
    end
  end
end
