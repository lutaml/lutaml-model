require "date"

module Lutaml
  module Model
    module Type
      # Date and time representation
      class DateTime
        def self.cast(value)
          return if value.nil?

          ::DateTime.parse(value.to_s).new_offset(0)
        end

        def self.serialize(value)
          value.iso8601
        end
      end
    end
  end
end
