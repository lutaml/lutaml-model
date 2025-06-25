# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class InvalidValueError < Error
        def initialize(value, allowed_values)
          @value = value
          @allowed_values = allowed_values

          super()
        end

        def to_s
          "`#{@value}` is invalid, must be one of the " \
            "following #{@allowed_values.inspect}"
        end
      end
    end
  end
end
