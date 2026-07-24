# frozen_string_literal: true

module Lutaml
  module Model
    class MinLengthError < RestrictionError
      def initialize(attr_name, value, min_length)
        @attr_name = attr_name
        @value = value
        @min_length = min_length

        super()
      end

      def to_s
        "#{@attr_name} length (#{@value.to_s.length}) is less than " \
          "the minimum required length #{@min_length}"
      end
    end
  end
end
