# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class MinLengthError < Error
        def initialize(value, min_length)
          @value = value
          @min_length = min_length

          super()
        end

        def to_s
          "String \"#{@value}\" length (#{@value.length}) is less than the minimum required length #{@min_length}"
        end
      end
    end
  end
end
