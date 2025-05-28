module Lutaml
  module Model
    class InvalidChoiceRangeError < Error
      def initialize(min, max)
        @min = min
        @max = max

        super()
      end

      def to_s
        bound_name, value = @min.negative? ? ["lower", @min] : ["upper", @max]

        "Choice #{bound_name} bound `#{value}` must be positive"
      end
    end
  end
end
