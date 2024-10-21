module Lutaml
  module Model
    class Sequence
      attr_reader :attributes,
                  :model

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
        namespace: nil,
        prefix: nil
      )
        @attributes << @model.map_element(
          name,
          to: to,
          render_nil: render_nil,
          render_default: render_default,
          with: with,
          delegate: delegate,
          cdata: cdata,
          namespace: namespace,
          prefix: prefix,
        )
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

      def validate_content!(element_order)
        defined_order = @attributes.map { |rule| rule.name.to_s }
        start_index = element_order.index(defined_order.first)

        defined_order.each.with_index(start_index) do |element, i|
          unless element_order[i] == element
            raise Lutaml::Model::IncorrectSequenceError.new(element, element_order[i])
          end
        end
      end
    end
  end
end
