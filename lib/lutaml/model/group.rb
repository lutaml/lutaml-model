module Lutaml
  module Model
    class Group
      attr_reader :attribute_tree,
                  :model

      def initialize(model)
        @attribute_tree = []
        @model = model
      end

      def attribute(_name, _type, _options = {})
        raise Lutaml::Model::InvalidGroupError.new("Attributes can't be defined directly in group")
      end

      def group
        raise Lutaml::Model::InvalidGroupError.new("Nested group definitions are not allowed")
      end

      def choice(&block)
        if @attribute_tree.size >= 1
          raise Lutaml::Model::InvalidGroupError.new("Can't define multiple choices in group")
        end

        @attribute_tree << Choice.new(@model).tap { |c| c.instance_eval(&block) }
      end

      def validate_content!(object, total_selected = [])
        attribute_tree.each do |attribute|
          attribute.validate_content!(object, total_selected)
        end
      end
    end
  end
end
