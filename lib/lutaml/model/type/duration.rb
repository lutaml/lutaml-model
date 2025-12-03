require_relative "value"

module Lutaml
  module Model
    module Type
      # ISO 8601 Duration type
      #
      # Handles durations in the format: P[n]Y[n]M[n]DT[n]H[n]M[n]S
      # Examples: "P1Y2M3D", "PT4H5M6S", "P1Y2M3DT4H5M6S"
      #
      # @example Using duration type
      #   attribute :processing_time, :duration
      class Duration < Value
        attr_reader :years, :months, :days, :hours, :minutes, :seconds

        def initialize(value)
          if value.is_a?(Duration)
            @years = value.years
            @months = value.months
            @days = value.days
            @hours = value.hours
            @minutes = value.minutes
            @seconds = value.seconds
            @value = value.to_s
          else
            @value = self.class.cast(value)
            parse_duration(@value) if @value
          end
        end

        def self.cast(value, _options = {})
          return nil if value.nil?
          return value.to_s if value.is_a?(Duration)
          return value if value.is_a?(::String) && valid_duration?(value)

          value.to_s
        end

        def self.serialize(value)
          return nil if value.nil?
          return value.to_s if value.is_a?(Duration)

          value.to_s
        end

        # XSD type for Duration
        #
        # @return [String] xs:duration
        def self.default_xsd_type
          "xs:duration"
        end

        def to_s
          @value
        end

        private

        def self.valid_duration?(str)
          # Basic ISO 8601 duration validation
          str.match?(/^P(?:\d+Y)?(?:\d+M)?(?:\d+D)?(?:T(?:\d+H)?(?:\d+M)?(?:\d+(?:\.\d+)?S)?)?$/)
        end

        def parse_duration(str)
          return unless str

          # Parse ISO 8601 duration string
          matches = str.match(/^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$/)
          return unless matches

          @years = matches[1].to_i
          @months = matches[2].to_i
          @days = matches[3].to_i
          @hours = matches[4].to_i
          @minutes = matches[5].to_i
          @seconds = matches[6].to_f
        end
      end
    end
  end
end
