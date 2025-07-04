# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class MaxLengthError < Error
        def initialize(value, max_length)
          @value = value
          @max_length = max_length

          super()
        end

        def to_s
          "String \"#{@value}\" length (#{@value.length}) is greater than the maximum allowed length #{@max_length}"
        end
      end
    end
  end
end
