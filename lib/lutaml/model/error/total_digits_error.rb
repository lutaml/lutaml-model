# frozen_string_literal: true

module Lutaml
  module Model
    class TotalDigitsError < RestrictionError
      def initialize(attr_name, value, total_digits)
        @attr_name = attr_name
        @value = value
        @total_digits = total_digits

        super()
      end

      def to_s
        "#{@attr_name} (#{@value}) exceeds the maximum of " \
          "#{@total_digits} total digits"
      end
    end
  end
end
