# frozen_string_literal: true

module Lutaml
  module Model
    class FractionDigitsError < RestrictionError
      def initialize(attr_name, value, fraction_digits)
        @attr_name = attr_name
        @value = value
        @fraction_digits = fraction_digits

        super()
      end

      def to_s
        "#{@attr_name} (#{@value}) exceeds the maximum of " \
          "#{@fraction_digits} fraction digits"
      end
    end
  end
end
