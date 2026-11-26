# frozen_string_literal: true

module Lutaml
  module Layout
    class Engine
      attr_accessor :input

      def initialize(input:)
        @input = input
      end

      def render(_type)
        raise ArgumentError, "Implement render method"
      end
    end
  end
end
