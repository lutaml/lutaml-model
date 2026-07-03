# frozen_string_literal: true

module Lutaml
  module Model
    class MaxLengthError < RestrictionError
      def initialize(attr_name, value, max_length)
        @attr_name = attr_name
        @value = value
        @max_length = max_length

        super()
      end

      def to_s
        "#{@attr_name} length (#{@value.to_s.length}) is greater than " \
          "the maximum allowed length #{@max_length}"
      end
    end
  end
end
