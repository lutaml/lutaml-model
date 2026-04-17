# frozen_string_literal: true

require "date"

module Lutaml
  module Model
    module Type
      class Date < Value
        # Matches timezone suffix in date strings: Z, +HH:MM, -HH:MM
        TIMEZONE_RE = /(Z|[+-]\d{2}:\d{2})\s*$/

        def self.cast(value, _options = {})
          return super if Utils.uninitialized?(value)
          return nil if value.nil?

          case value
          when ::DateTime
            # Preserve timezone by keeping as DateTime at midnight
            ::DateTime.new(value.year, value.month, value.mday, 0, 0, 0,
                           value.offset)
          when ::Time
            value.to_date
          when ::Date
            value
          else
            str = value.to_s
            tz_match = str.match(TIMEZONE_RE)
            if tz_match
              date = ::Date.parse(str.sub(TIMEZONE_RE, ""))
              offset = parse_timezone(tz_match[1])
              ::DateTime.new(date.year, date.month, date.mday, 0, 0, 0, offset)
            else
              ::Date.parse(str)
            end
          end
        rescue ArgumentError
          nil
        end

        # xs:date format with optional timezone
        def self.serialize(value)
          return nil if value.nil?

          case value
          when ::DateTime
            value.strftime("%Y-%m-%d%:z")
          else
            value.iso8601
          end
        end

        # Default XSD type for Date
        #
        # @return [String] xs:date
        def self.default_xsd_type
          "xs:date"
        end

        # Parse timezone string to Rational offset (fraction of day)
        #
        # @param tz [String] timezone string (Z, +HH:MM, -HH:MM)
        # @return [Rational] offset as fraction of day
        def self.parse_timezone(offset_str)
          return Rational(0) if offset_str == "Z"

          sign = offset_str.start_with?("-") ? -1 : 1
          parts = offset_str.delete("+-").split(":")
          hours = parts[0].to_i
          minutes = parts[1].to_i
          Rational(sign * ((hours * 60) + minutes), 1440)
        end
      end
    end
  end
end
