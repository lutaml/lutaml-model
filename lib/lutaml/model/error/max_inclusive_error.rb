# frozen_string_literal: true

module Lutaml
  module Model
    class MaxInclusiveError < RestrictionError
      def initialize(attr_name, value, max)
        @attr_name = attr_name
        @value = value
        @max = max

        super()
      end

      def to_s
        "#{@attr_name} is `#{@value}`, " \
          "must be less than or equal to #{@max}"
      end
    end
  end
end
