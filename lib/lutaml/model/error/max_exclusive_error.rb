# frozen_string_literal: true

module Lutaml
  module Model
    class MaxExclusiveError < RestrictionError
      def initialize(attr_name, value, max)
        @attr_name = attr_name
        @value = value
        @max = max

        super()
      end

      def to_s
        "#{@attr_name} is `#{@value}`, must be less than #{@max}"
      end
    end
  end
end
