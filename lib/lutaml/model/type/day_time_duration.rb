# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema day-time-duration datatype (#107): an ISO 8601
      # duration expressed in days, hours, minutes, and seconds (no
      # years or months), per the xs:dayTimeDuration form. Built by
      # interpolation with no formatting whitespace, so the pattern's
      # source is export-clean for xs:pattern facets.
      #
      # @example Using DayTimeDuration type
      #   attribute :elapsed, :day_time_duration
      class DayTimeDuration < Duration
        ELAPSED_TIME =
          "(?:[0-9]+H(?:[0-9]+M)?(?:[0-9]+(?:\\.[0-9]+)?S)?" \
          "|[0-9]+M(?:[0-9]+(?:\\.[0-9]+)?S)?" \
          "|[0-9]+(?:\\.[0-9]+)?S)"
        PATTERN = /\A-?P(?:[0-9]+D(?:T#{ELAPSED_TIME})?|T#{ELAPSED_TIME})\z/

        def self.valid?(value)
          value.is_a?(::String) ? value.match?(PATTERN) : !cast(value).nil?
        end

        def self.json_schema_format
          "duration"
        end

        def self.default_xsd_type
          "xs:dayTimeDuration"
        end
      end
    end
  end
end
