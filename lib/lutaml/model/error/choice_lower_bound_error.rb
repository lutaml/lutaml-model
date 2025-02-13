module Lutaml
  module Model
    class ChoiceLowerBoundError < Error
      def initialize(validated_attributes, min)
        validated_attributes = flatten_nested_attributes(validated_attributes, Lutaml::Model::Choice)
        super("Attributes `#{validated_attributes}` count is less than the lower bound `#{min}`")
      end
    end
  end
end
