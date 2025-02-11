module Lutaml
  module Model
    class ChoiceLowerBoundError < Error
      def initialize(validated_attributes, min)
        validated_attributes.map! do |attr|
          attr.is_a?(Lutaml::Model::Choice) ? attr.attributes.map(&:name) : attr
        end.flatten!

        super("Attributes `#{validated_attributes}` count is less than the lower bound `#{min}`")
      end
    end
  end
end
