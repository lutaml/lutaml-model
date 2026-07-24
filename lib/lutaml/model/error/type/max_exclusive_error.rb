# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class MaxExclusiveError < Error
        def initialize(value, max_bound)
          @value = value
          @max_bound = max_bound

          super()
        end

        def to_s
          "Value #{@value} is not less than the exclusive maximum #{@max_bound}"
        end
      end
    end
  end
end
