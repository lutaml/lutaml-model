# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class MinExclusiveError < Error
        def initialize(value, min_bound)
          @value = value
          @min_bound = min_bound

          super()
        end

        def to_s
          "Value #{@value} is not greater than the exclusive minimum #{@min_bound}"
        end
      end
    end
  end
end
