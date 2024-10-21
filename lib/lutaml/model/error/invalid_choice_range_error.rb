module Lutaml
  module Model
    class InvalidChoiceRangeError < Error
      def initialize(min, max)
        @min = min
        @max = max

        super()
      end

      def to_s
        if @min.negative?
          "Choice lower bound `#{@min}` must be positive"
        else
          "Choice upper bound `#{@max}` must be positive"
        end
      end
    end
  end
end
