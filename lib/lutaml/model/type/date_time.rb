require "date"

module Lutaml
  module Model
    module Type
      # Date and time representation
      class DateTime < Value
        def self.cast(value)
          return if value.nil?

          ::DateTime.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def self.serialize(value)
          value&.iso8601
        end
      end
    end
  end
end
