# frozen_string_literal: true

require "time"

module Lutaml
  module Model
    module Type
      class Time < Value
        def self.cast(value, _options = {})
          return super if Utils.uninitialized?(value)
          return nil if value.nil?

          case value
          when ::Time then value
          when ::DateTime then value.to_time
          when ::Integer
            # YAML 1.1 sexagesimal: psych resolves an unquoted hh:mm:ss
            # scalar to seconds since midnight (25200 for "07:00:00").
            # Feeding that integer through Time.parse yields a garbage
            # date — reconstruct the wall-clock time of the current day.
            ::Date.today.to_time + value
          else ::Time.parse(value.to_s)
          end
        rescue ArgumentError
          nil
        end

        def self.serialize(value)
          return nil if value.nil?

          time = cast(value)
          return nil unless time

          # Only include fractional seconds if they exist
          if time.subsec.zero?
            time.iso8601
          else
            # Keep minimum 3 decimal places, remove last 3 zeros if present
            time.iso8601(6).sub(/(\.\d{3})0{3}([+-])/, '\1\2')
          end
        end

        # XSD type for Time
        #
        # @return [String] xs:time
        def self.default_xsd_type
          "xs:time"
        end
      end
    end
  end
end
