# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # XML Schema gMonth datatype: a calendar month — --11, --11Z, --11+05:30.
      #
      # @example Using GMonth type
      #   attribute :renews_in, :g_month
      class GMonth < String
        PATTERN = /\A--(?:0[1-9]|1[0-2])(Z|[+-]\d{2}:\d{2})?\z/

        def self.cast(value, _options = EMPTY_OPTIONS)
          value&.to_s
        end

        def self.valid?(value)
          value.is_a?(::String) ? value.match?(PATTERN) : !cast(value).nil?
        end

        def self.json_schema_format
          "gmonth"
        end

        def self.default_xsd_type
          "xs:gMonth"
        end
      end
    end
  end
end
