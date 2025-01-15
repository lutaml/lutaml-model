# frozen_string_literal: true

module Lutaml
  module Model
    module Type
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
end
