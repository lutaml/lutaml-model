require "json"

module Lutaml
  module Model
    module Type
      # JSON representation
      class Json
        attr_reader :value

        def initialize(value)
          @value = value
        end

        def to_json(*_args)
          @value.to_json
        end

        def ==(other)
          @value == (other.is_a?(::Hash) ? other : other.value)
        end

        def self.cast(value)
          return value if value.is_a?(self) || value.nil?

          new(::JSON.parse(value))
        end

        def self.serialize(value)
          value.to_json
        end
      end
    end
  end
end
