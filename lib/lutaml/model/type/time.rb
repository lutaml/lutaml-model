require "time"

module Lutaml
  module Model
    module Type
      class Time < Value
        def self.cast(value)
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

          value = cast(value)
          # value&.strftime("%Y-%m-%dT%H:%M:%S%:z")
          value&.iso8601
        end

        # # xs:time format (HH:MM:SS.mmm±HH:MM)
        def to_xml
          value&.iso8601
        end

        # # ISO8601 time format
        # def to_json
        #   value&.iso8601
        # end

        # YAML timestamp format (native)
        def to_yaml
          value&.iso8601
        end

        # # TOML time format (HH:MM:SS.mmm)
        # def to_toml
        #   value&.strftime("%H:%M:%S.%L")
        # end
      end
    end
  end
end
