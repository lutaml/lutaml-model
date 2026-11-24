# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # XML Schema gYear datatype: a calendar year — 2026, 0942, 2026Z,
      # 2026+05:30.
      #
      # @example Using GYear type
      #   attribute :reported, :g_year
      class GYear < String
        PATTERN = /\A-?\d{4,}(Z|[+-]\d{2}:\d{2})?\z/

        def self.cast(value, _options = EMPTY_OPTIONS)
          value.nil? ? nil : value.to_s
        end

        def self.valid?(value)
          value.is_a?(::String) ? value.match?(PATTERN) : !cast(value).nil?
        end

        def self.json_schema_format
          "gyear"
        end

        def self.default_xsd_type
          "xs:gYear"
        end
      end
    end
  end
end
