# frozen_string_literal: true

module Lutaml
  module Model
    class MinInclusiveError < RestrictionError
      def initialize(attr_name, value, min)
        @attr_name = attr_name
        @value = value
        @min = min

        super()
      end

      def to_s
        "#{@attr_name} is `#{@value}`, " \
          "must be greater than or equal to #{@min}"
      end
    end
  end
end
