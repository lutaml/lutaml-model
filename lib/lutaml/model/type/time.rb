require "time"

module Lutaml
  module Model
    module Type
      class Time < Value
        def self.cast(value, _options = {})
          return value if value.nil? || Utils.uninitialized?(value)

          case value
          when ::Time then value
          when ::DateTime then value.to_time
          else ::Time.parse(value.to_s)
          end
        rescue ArgumentError
          nil
        end

        def self.serialize(value)
          return value if value.nil? || Utils.uninitialized?(value)

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

        # # xs:time format (HH:MM:SS.mmm±HH:MM)
        def to_xml
          return nil unless value

          if value.subsec.zero?
            value.iso8601
          else
            value.iso8601(6).sub(/(\.\d{3})0{3}([+-])/, '\1\2')
          end
        end

        # # ISO8601 time format
        # def to_json
        #   value&.iso8601
        # end

        # YAML timestamp format (native)
        def to_yaml
          return nil unless value

          if value.subsec.zero?
            value.iso8601
          else
            value.iso8601(6).sub(/(\.\d{3})0{3}([+-])/, '\1\2')
          end
        end

        # # TOML time format (HH:MM:SS.mmm)
        # def to_toml
        #   value&.strftime("%H:%M:%S.%L")
        # end
      end
    end
  end
end
