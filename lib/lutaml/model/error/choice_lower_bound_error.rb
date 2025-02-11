module Lutaml
  module Model
    class ChoiceLowerBoundError < Error
      def initialize(validated_attributes, min)
        super("Attributes `#{extract_attribute_names(validated_attributes, Lutaml::Model::Choice)}` count is less than the lower bound `#{min}`")
      end
    end
  end
end
