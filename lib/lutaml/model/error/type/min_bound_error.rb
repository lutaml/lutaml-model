# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class MinBoundError < Error
        def initialize(value, min_bound)
          @value = value
          @min_bound = min_bound

          super()
        end

        def to_s
          "Value #{@value} is less than the set minimum limit #{@min_bound}"
        end
      end
    end
  end
end
