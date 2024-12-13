module Lutaml
  module Model
    class InvalidValueError < Error
      def initialize(message)
        @message = message

        super()
      end

      def to_s
        @message
      end
    end
  end
end
