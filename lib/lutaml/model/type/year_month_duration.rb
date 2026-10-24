# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema year-month-duration datatype (#107): an ISO 8601
      # duration expressed in years and months (no time components), per
      # the xs:yearMonthDuration form — P1Y6M, -P9M, P10M.
      #
      # @example Using YearMonthDuration type
      #   attribute :term, :year_month_duration
      class YearMonthDuration < Duration
        PATTERN = /\A-?P(?:[0-9]+Y(?:[0-9]+M)?|[0-9]+M)\z/

        def self.valid?(value)
          value.is_a?(::String) ? value.match?(PATTERN) : !cast(value).nil?
        end

        def self.json_schema_format
          "duration"
        end

        def self.default_xsd_type
          "xs:yearMonthDuration"
        end
      end
    end
  end
end
