# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class MaxBoundError < Error
        def initialize(value, max_bound)
          @value = value
          @max_bound = max_bound

          super()
        end

        def to_s
          "Value #{@value} is greater than the set maximum limit #{@max_bound}"
        end
      end
    end
  end
end
