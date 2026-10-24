# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema date-time-with-timezone datatype (#107): a
      # date-time that must carry a UTC offset or Z.
      #
      # @example Using DateTimeWithTimezone type
      #   attribute :generated_at, :date_time_with_timezone
      class DateTimeWithTimezone < DateTime
        TIMEZONE = /(Z|[+-]\d{2}:\d{2})\z/

        def self.valid?(value)
          value.is_a?(::String) ? value.match?(TIMEZONE) : !cast(value).nil?
        end

        def self.json_schema_format
          "date-time"
        end

        def self.default_xsd_type
          "xs:dateTime"
        end
      end
    end
  end
end
