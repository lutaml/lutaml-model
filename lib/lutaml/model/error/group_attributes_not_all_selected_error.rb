module Lutaml
  module Model
    class GroupAttributeNotAllSelectedError < Error
      def initialize(attr_names)
        @attr_names = attr_names

        super()
      end

      def to_s
        "#{@attr_names} is missing or nil, check his group"
      end
    end
  end
end
