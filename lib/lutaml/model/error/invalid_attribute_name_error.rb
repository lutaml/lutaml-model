module Lutaml
  module Model
    class InvalidAttributeNameError < Error
      def initialize(name)
        @name = name

        super()
      end

      def to_s
        "Attribute name '#{@name}' is not allowed"
      end
    end
  end
end
