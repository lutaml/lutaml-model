module Lutaml
  module Model
    class ElementCountOutOfRangeError < Error
      def initialize(attr_name, value, range)
        @attr_name = attr_name
        @value = value
        @range = range

        super()
      end

      def to_s
        "#{@attr_name} count is #{@value}, expected to appear between #{@range.min} and #{@range.max}"
      end
    end
  end
end
