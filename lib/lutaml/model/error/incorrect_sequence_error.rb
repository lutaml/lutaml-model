module Lutaml
  module Model
    class IncorrectSequenceError < Error
      def initialize(defined_order_element, expected_order_element)
        super("Element `#{expected_order_element}` does not match the expected sequence order element `#{defined_order_element}`")
      end
    end
  end
end
