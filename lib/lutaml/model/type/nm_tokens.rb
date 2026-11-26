# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # XML Schema NMTOKENS datatype: a whitespace-separated list of
      # NMTOKEN values — "en-US de-DE", "en-US".
      #
      # @example Using NmTokens type
      #   attribute :locales, :nmtokens
      class NmTokens < String
        NMTOKEN = /[\w.:-]+/
        PATTERN = /\A#{NMTOKEN}(?:\s+#{NMTOKEN})*\z/

        def self.cast(value, _options = EMPTY_OPTIONS)
          value&.to_s
        end

        def self.valid?(value)
          value.is_a?(::String) ? value.match?(PATTERN) : !cast(value).nil?
        end

        def self.json_schema_format
          "nmtokens"
        end

        def self.default_xsd_type
          "xs:NMTOKENS"
        end
      end
    end
  end
end
