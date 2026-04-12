# frozen_string_literal: true

module Lutaml
  module Model
    class PatternContentRule < ConsolidationRule
      attr_reader :target

      # @param target [Symbol] attribute name on GroupClass
      def initialize(target)
        super
        @target = target
      end
    end
  end
end
