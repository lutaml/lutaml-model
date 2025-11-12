require "date"

module Lutaml
  module Model
    module Type
      # Date and time representation
      class DateTime < Value
        def self.cast(value, _options = {})
          return value if value.nil? || Utils.uninitialized?(value)

          case value
          when ::DateTime then value
          when ::Time then value.to_datetime
          else ::DateTime.parse(value.to_s)
          end
        rescue ArgumentError
          nil
        end

        def self.serialize(value)
          return value if value.nil? || Utils.uninitialized?(value)

          dt = cast(value)
          return nil unless dt

          # Only include fractional seconds if they exist
          if dt.sec_fraction.zero?
            dt.iso8601
          else
            # Keep minimum 3 decimal places, remove last 3 zeros if present
            dt.iso8601(6).sub(/(\.\d{3})0{3}([+-])/, '\1\2')
          end
        end

        # xs:dateTime format (ISO8601 with timezone)
        def to_xml
          return nil unless value

          if value.sec_fraction.zero?
            value.iso8601
          else
            value.iso8601(6).sub(/(\.\d{3})0{3}([+-])/, '\1\2')
          end
        end

        # RFC3339 (ISO8601 with timezone)
        def to_json(*_args)
          return nil unless value

          if value.sec_fraction.zero?
            value.iso8601
          else
            value.iso8601(6).sub(/(\.\d{3})0{3}([+-])/, '\1\2')
          end
        end

        # YAML timestamp format (native)
        def to_yaml
          return nil unless value

          if value.sec_fraction.zero?
            value.iso8601
          else
            value.iso8601(6).sub(/(\.\d{3})0{3}([+-])/, '\1\2')
          end
        end

        # TOML datetime format (RFC3339)
        def to_toml
          return nil unless value

          if value.sec_fraction.zero?
            value.iso8601
          else
            value.iso8601(6).sub(/(\.\d{3})0{3}([+-])/, '\1\2')
          end
        end
      end
    end
  end
end
