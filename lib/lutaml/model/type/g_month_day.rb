# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # XML Schema gMonthDay datatype: a recurring calendar day —
      # --11-24, --11-24Z, --11-24+05:30.
      #
      # @example Using GMonthDay type
      #   attribute :anniversary, :g_month_day
      class GMonthDay < String
        PATTERN = /\A--(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])(Z|[+-]\d{2}:\d{2})?\z/

        def self.cast(value, _options = EMPTY_OPTIONS)
          value&.to_s
        end

        def self.valid?(value)
          value.is_a?(::String) ? value.match?(PATTERN) : !cast(value).nil?
        end

        def self.json_schema_format
          "gmonthday"
        end

        def self.default_xsd_type
          "xs:gMonthDay"
        end
      end
    end
  end
end
