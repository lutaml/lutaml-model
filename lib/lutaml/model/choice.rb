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
        group_choice_helper(Group.new(@model), &block)
      end

      def choice(&block)
        group_choice_helper(Choice.new(@model), &block)
      end

      def validate_count!(object, total_attrs = [])
        @attribute_tree.each do |attribute|
          attribute.validate_count!(object, total_attrs)
        end

        unless total_attrs.length == 1
          raise Lutaml::Model::InvalidChoiceError.new
        end
      end

      private

      def group_choice_helper(nested_option, &block)
        nested_option.instance_eval(&block)
        @attribute_tree << nested_option
      end
    end
  end
end
