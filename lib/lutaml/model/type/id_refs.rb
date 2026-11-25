# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # XML Schema IDREFS datatype: a whitespace-separated list of IDREF
      # values — "a1 b2", "a1".
      #
      # @example Using IdRefs type
      #   attribute :see_also, :idrefs
      class IdRefs < String
        IDREF = /[a-zA-Z_][\w.-]*/
        PATTERN = /\A#{IDREF}(?:\s+#{IDREF})*\z/

        def self.cast(value, _options = EMPTY_OPTIONS)
          value&.to_s
        end

        def self.valid?(value)
          value.is_a?(::String) ? value.match?(PATTERN) : !cast(value).nil?
        end

        def self.json_schema_format
          "idrefs"
        end

        def self.default_xsd_type
          "xs:IDREFS"
        end
      end
    end
  end
end
