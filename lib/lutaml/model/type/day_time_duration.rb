# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema day-time-duration datatype (#107): an ISO 8601
      # duration expressed in days, hours, minutes, and seconds (no
      # years or months), per the xs:dayTimeDuration form.
      #
      # @example Using DayTimeDuration type
      #   attribute :elapsed, :day_time_duration
      class DayTimeDuration < Duration
        ELAPSED_TIME =
          /(?:[0-9]+H(?:[0-9]+M)?(?:[0-9]+(?:\.[0-9]+)?S)?
                 |[0-9]+M(?:[0-9]+(?:\.[0-9]+)?S)?
                 |[0-9]+(?:\.[0-9]+)?S)/x
        PATTERN = /
          \A-?P(?:[0-9]+D(?:T#{ELAPSED_TIME.source})?|T#{ELAPSED_TIME.source})\z
        /x

        def self.valid?(value)
          value.is_a?(::String) ? value.match?(PATTERN) : !cast(value).nil?
        end

        def self.default_xsd_type
          "xs:dayTimeDuration"
        end
      end
    end
  end
end
