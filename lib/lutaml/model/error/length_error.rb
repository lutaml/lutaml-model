# frozen_string_literal: true

module Lutaml
  module Model
    class LengthError < RestrictionError
      def initialize(attr_name, value, length)
        @attr_name = attr_name
        @value = value
        @length = length

        super()
      end

      def to_s
        "#{@attr_name} length (#{@value.to_s.length}) must be exactly #{@length}"
      end
    end
  end
end
