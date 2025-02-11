module Lutaml
  module Model
    class ChoiceUpperBoundError < Error
      def initialize(validated_attributes, max)
        validated_attributes.map! do |attr|
          attr.is_a?(Lutaml::Model::Choice) ? attr.attributes.map(&:name) : attr
        end.flatten!         

        super("Attributes `#{validated_attributes}` count exceeds the upper bound `#{max}`")
      end
    end
  end
end
