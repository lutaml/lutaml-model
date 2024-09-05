module Lutaml
  module Model
    class CollectionCountOutOfRangeError < Error
      def initialize(attr_name, value, range)
        @attr_name = attr_name
        @value = value
        @range = range

        super()
      end

      def to_s
        "#{@attr_name} count is `#{@value.count}`, must be between " \
          "#{range_to_string} "
      end

      private

      def range_to_string
        "#{@range.first} and #{@range.last(1).first}"
      end
    end
  end
end
