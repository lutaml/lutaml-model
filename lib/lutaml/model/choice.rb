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
        @attribute_tree << Group.new(@model).tap { |g| g.instance_eval(&block) }
      end

      def choice(&block)
        @attribute_tree << Choice.new(@model).tap { |c| c.instance_eval(&block) }
      end

      def validate_content!(object, total_attrs = [])
        @attribute_tree.each do |attribute|
          attribute.validate_content!(object, total_attrs)
        end

        unless total_attrs.length == 1
          raise Lutaml::Model::InvalidChoiceError.new
        end
      end
    end
  end
end
