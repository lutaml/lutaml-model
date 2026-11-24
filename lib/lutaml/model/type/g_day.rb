# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # XML Schema gDay datatype: a recurring calendar day of month —
      # ---24, ---24Z, ---24+05:30.
      #
      # @example Using GDay type
      #   attribute :closes_on, :g_day
      class GDay < String
        PATTERN = /\A---(?:0[1-9]|[12]\d|3[01])(Z|[+-]\d{2}:\d{2})?\z/

        def self.cast(value, _options = EMPTY_OPTIONS)
          value.nil? ? nil : value.to_s
        end

        def self.valid?(value)
          value.is_a?(::String) ? value.match?(PATTERN) : !cast(value).nil?
        end

        def self.json_schema_format
          "gday"
        end

        def self.default_xsd_type
          "xs:gDay"
        end
      end
    end
  end
end
