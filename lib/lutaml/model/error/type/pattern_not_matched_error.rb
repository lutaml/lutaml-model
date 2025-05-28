module Lutaml
  module Model
    module Type
      class PatternNotMatchedError < Error
        def initialize(value, pattern)
          @pattern = pattern
          @value = value

          super()
        end

        def to_s
          "\"#{@value}\" does not match #{@pattern.inspect}"
        end
      end
    end
  end
end
