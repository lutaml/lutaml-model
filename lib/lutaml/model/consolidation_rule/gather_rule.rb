# frozen_string_literal: true

module Lutaml
  module Model
    class GatherRule < ConsolidationRule
      attr_reader :source, :target

      # @param source [Symbol] attribute name on raw items
      # @param target [Symbol] attribute name on GroupClass
      def initialize(source, target)
        super
        @source = source
        @target = target
      end
    end
  end
end
