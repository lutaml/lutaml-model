module Lutaml
  module Model
    class ChoiceLowerBoundError < Error
      def initialize(validated_attributes, min)
        super("Attributes `#{validated_attributes}` count is less than the lower bound `#{min}`")
      end
    end
  end
end
