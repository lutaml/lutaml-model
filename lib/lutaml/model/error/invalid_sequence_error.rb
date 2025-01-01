module Lutaml
  module Model
    class InvalidSequenceError < Error
      def to_s
        "Elements must be present in the specified order"
      end
    end
  end
end
