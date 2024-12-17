module Lutaml
  module Model
    class Choice
      attr_reader :attribute_tree,
                  :model

      def initialize(model)
        @attribute_tree = []
        @model = model
      end

      def attribute(name, type, options = {})
        options[:parent_choice] = self
        @attribute_tree << @model.attribute(name, type, options)
      end

      def group(&block)
        process_nested_structure(Group.new(@model), &block)
      end

      def choice(&block)
        process_nested_structure(Choice.new(@model), &block)
      end

      def sequence(&block)
        process_nested_structure(Sequence.new(@model), &block)
      end

      def validate_content!(object, validated_attributes = [], defined_order = [])
        sequence_error = false
        @attribute_tree.each do |attribute|
          attribute.validate_content!(object, validated_attributes, defined_order)
        rescue Lutaml::Model::InvalidSequenceError
          sequence_error = true if validated_attributes.count == 1
        end

        if validated_attributes.count != 1 || sequence_error
          raise Lutaml::Model::InvalidChoiceError.new
        end
      end

      private

      def process_nested_structure(nested_option, &block)
        nested_option.instance_eval(&block)
        @attribute_tree << nested_option
      end
    end
  end
end
