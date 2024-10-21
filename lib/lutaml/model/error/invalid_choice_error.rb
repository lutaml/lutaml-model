module Lutaml
  module Model
    class InvalidChoiceError < Error
      def to_s
        "Exactly one attribute must be specified in a choice"
      end
    end
  end
end
