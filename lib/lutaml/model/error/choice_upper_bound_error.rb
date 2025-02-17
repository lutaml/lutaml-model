module Lutaml
  module Model
    class ChoiceUpperBoundError < Error
      def initialize(validated_attributes, max)
        super("Attributes `#{validated_attributes}` count exceeds the upper bound `#{max}`")
      end
    end
  end
end
