# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # Facet container for restricted simple types. Every field is
        # optional; nil means "facet not present".
        class Facet
          attr_accessor :min_inclusive, :max_inclusive,
                        :min_exclusive, :max_exclusive,
                        :pattern, :enumerations,
                        :min_length, :max_length, :length,
                        :total_digits, :fraction_digits,
                        :white_space

          def initialize(min_inclusive: nil, max_inclusive: nil,
                         min_exclusive: nil, max_exclusive: nil,
                         pattern: nil, enumerations: nil,
                         min_length: nil, max_length: nil, length: nil,
                         total_digits: nil, fraction_digits: nil,
                         white_space: nil)
            @min_inclusive = min_inclusive
            @max_inclusive = max_inclusive
            @min_exclusive = min_exclusive
            @max_exclusive = max_exclusive
            @pattern = pattern
            @enumerations = enumerations
            @min_length = min_length
            @max_length = max_length
            @length = length
            @total_digits = total_digits
            @fraction_digits = fraction_digits
            @white_space = white_space
          end
        end
      end
    end
  end
end
