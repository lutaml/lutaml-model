# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema positive-integer datatype (#107): an integer
      # greater than 0 (xs:positiveInteger).
      #
      # @example Using PositiveInteger type
      #   attribute :ordinal, :positive_integer
      class PositiveInteger < Integer
        def self.valid?(value)
          cast_value = cast(value)

          cast_value.is_a?(::Integer) && cast_value >= 1
        end

        def self.default_xsd_type
          "xs:positiveInteger"
        end
      end
    end
  end
end
