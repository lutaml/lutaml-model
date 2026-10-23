# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema date-with-timezone datatype (#107): a date that
      # must carry a UTC offset or Z.
      #
      # @example Using DateWithTimezone type
      #   attribute :effective_on, :date_with_timezone
      class DateWithTimezone < Date
        TIMEZONE = /(Z|[+-]\d{2}:\d{2})\z/

        def self.valid?(value)
          value.is_a?(::String) ? value.match?(TIMEZONE) : !cast(value).nil?
        end

        def self.default_xsd_type
          "xs:date"
        end
      end
    end
  end
end
