# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema non-negative-integer datatype (#107): an integer
      # equal to or greater than 0 (xs:nonNegativeInteger).
      #
      # @example Using NonNegativeInteger type
      #   attribute :index, :non_negative_integer
      class NonNegativeInteger < Integer
        def self.valid?(value)
          cast_value = cast(value)

          cast_value.is_a?(::Integer) && cast_value >= 0
        end

        def self.default_xsd_type
          "xs:nonNegativeInteger"
        end
      end
    end
  end
end
