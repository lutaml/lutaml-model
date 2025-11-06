module Lutaml
  module Model
    class ElementCountOutOfRangeError < Error
      def initialize(attr_name, appearance_count, range)
        @attr_name = attr_name
        @appearance_count = appearance_count
        @range = range

        super()
      end

      def to_s
        "`#{@attr_name}` expected to appear #{appearance} time(s), but #{times_appeared}."
      end

      private

      def appearance
        if @range.min == @range.max
          @range.min
        else
          "between '#{@range.min}' and '#{@range.max}'"
        end
      end

      def times_appeared
        if @appearance_count&.zero?
          "never appeared"
        else
          "appeared#{' only' if @appearance_count < @range.max} #{@appearance_count} time(s)"
        end
      end
    end
  end
end
