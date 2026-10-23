# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema uuid datatype (#107): an RFC4122 UUID, restricted
      # to versions 4 and 5 and the standard variant, per the
      # metaschema-datatypes pattern.
      #
      # @example Using Uuid type
      #   attribute :identifier, :uuid
      class Uuid < String
        extend MetaschemaPattern

        PATTERN = %r{\A[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[45][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}\z}

        def self.default_xsd_type
          "xs:string"
        end
      end
    end
  end
end
