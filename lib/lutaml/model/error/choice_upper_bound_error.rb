module Lutaml
  module Model
    class ChoiceUpperBoundError < Error
      def initialize(validated_attributes, max)
        validated_attributes = flatten_nested_attributes(validated_attributes, Lutaml::Model::Choice)
        super("Attributes `#{validated_attributes}` count exceeds the upper bound `#{max}`")
      end
    end
  end
end
