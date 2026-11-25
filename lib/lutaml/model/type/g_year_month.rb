# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # XML Schema gYearMonth datatype: a calendar year and month —
      # 2026-11, 0942-01Z, 2026-11+05:30.
      #
      # @example Using GYearMonth type
      #   attribute :issued, :g_year_month
      class GYearMonth < String
        PATTERN = /\A-?\d{4,}-(?:0[1-9]|1[0-2])(Z|[+-]\d{2}:\d{2})?\z/

        def self.cast(value, _options = EMPTY_OPTIONS)
          value&.to_s
        end

        def self.valid?(value)
          value.is_a?(::String) ? value.match?(PATTERN) : !cast(value).nil?
        end

        def self.json_schema_format
          "gyearmonth"
        end

        def self.default_xsd_type
          "xs:gYearMonth"
        end
      end
    end
  end
end
