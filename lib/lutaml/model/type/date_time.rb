require "date"

# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # Date and time representation
      class DateTime < Value
        def self.cast(value, _options = {})
          return super if Utils.uninitialized?(value)
          return nil if value.nil?

          # If already a DateTime type wrapper, return as-is
          return value if value.is_a?(self)

          case value
          when ::DateTime then value
          when ::Time then value.to_datetime
          else ::DateTime.parse(value.to_s)
          end
        rescue ArgumentError
          nil
        end

        def self.serialize(value)
          return nil if value.nil?

          dt = cast(value)
          return nil unless dt

          format_datetime_iso8601(dt)
        end

        # Format DateTime as ISO8601 string preserving fractional seconds and timezone offset.
        # Keeps up to 6 decimal places, strips trailing zeros beyond 3.
        #
        # @param datetime [DateTime] the DateTime to format
        # @return [String] ISO8601 formatted string, e.g. "2024-01-01T12:00:00.123+08:00"
        def self.format_datetime_iso8601(datetime)
          if datetime.sec_fraction.zero?
            datetime.iso8601
          else
            # iso8601(6) produces exactly 6 decimal places
            # e.g. 0.5s -> "0.500000", 0.123456s -> "0.123456"
            # Strip trailing zeros beyond 3 decimal places: ".500000" -> ".500"
            datetime.iso8601(6).sub(/(\.\d{3})0{3}([+-])/, '\1\2')
          end
        end

        # Default XSD type for DateTime
        #
        # @return [String] xs:dateTime
        def self.default_xsd_type
          "xs:dateTime"
        end
      end
    end
  end
end
