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
        "`#{@attr_name}` expected to appear between '#{@range.min}' and '#{@range.max}' time#{times_plural(@range.max)}, but #{times_appeared}."
      end

      private

      def times_appeared
        return "never appeared" if @appearance_count&.zero?

        "appeared only #{@appearance_count} time#{times_plural(@appearance_count)}"
      end

      def times_plural(count)
        "s" if count > 1
      end
    end
  end
end
