# frozen_string_literal: true

module Lutaml
  module Model
    class PatternElementRule < ConsolidationRule
      attr_reader :element_name, :target

      # @param element_name [String] XML element name
      # @param target [Symbol] attribute name on GroupClass
      def initialize(element_name, target)
        super
        @element_name = element_name
        @target = target
      end
    end
  end
end
