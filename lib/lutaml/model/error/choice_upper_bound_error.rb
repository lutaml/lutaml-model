module Lutaml
  module Model
    class ChoiceUpperBoundError < Error
      def initialize(validated_attributes, max)
        super("Attributes `#{flatten_objects(validated_attributes, Lutaml::Model::Choice)}` count exceeds the upper bound `#{max}`")
      end
    end
  end
end
