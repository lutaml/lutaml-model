module Lutaml
  module Model
    class Sequence
      attr_reader :attribute_tree,
                  :model

      def initialize(model)
        @attribute_tree = []
        @model = model
      end

      def attribute(name, type, options = {})
        options[:parent_sequence] = self
        @attribute_tree << @model.attribute(name, type, options)
      end

      def group(&block)
        @attribute_tree << Group.new(@model).tap { |g| g.instance_eval(&block) }
      end

      def choice(&block)
        @attribute_tree << Choice.new(@model).tap { |c| c.instance_eval(&block) }
      end

      def sequence(&block)
        @attribute_tree << Sequence.new(@model).tap { |s| s.instance_eval(&block) }
      end

      def validate_content!(object, validated_attributes = [], defined_order = [])
        @attribute_tree.each do |attribute|
          process_attribute(object, attribute, validated_attributes, defined_order)
          validated_attributes.clear
        end

        if object.element_order
          current_order = object.element_order&.reject { |e| e == "text" }
          validate_order(defined_order, current_order, validated_attributes)
        end
      end

      private

      def process_attribute(object, attr, validated_attributes, defined_order)
        if object.element_order && attr.is_a?(Lutaml::Model::Attribute)
          defined_order << attr.name.to_s
        else
          attr.validate_content!(object, validated_attributes, defined_order)
        end
      end

      def validate_order(defined_order, current_order, validated_attributes = [])
        index = current_order.index(defined_order.first)
        current_order = current_order[index..]

        defined_order.each do |element|
          if element == current_order.first
            current_order.shift
          else
            defined_order.clear
            raise Lutaml::Model::InvalidSequenceError.new
          end
        end

        validated_attributes << self
      end
    end
  end
end
