module Lutaml
  module Model
    class ElementCountOutOfRangeError < Error
      def initialize(attr_name, occurrence_count, range)
        @attr_name = attr_name
        @occurrence_count = occurrence_count
        @range = range

        super()
      end

      def to_s
        "`#{@attr_name}` expected to appear between '#{@range.min}' and '#{@range.max}' times, but #{times_occurred}."
      end

      private

      def times_occurred
        return "never occurred" if @occurrence_count&.zero?

        "appeared only #{@occurrence_count} time#{'s' if @occurrence_count > 1}"
      end
    end
  end
end
