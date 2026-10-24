# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema token datatype (#107): an XML NMTOKEN-like value —
      # a letter or underscore followed by letters, numbers, and the
      # punctuation `.-_` — per the metaschema-datatypes pattern.
      #
      # @example Using Token type
      #   attribute :label, :token
      class Token < String
        extend MetaschemaPattern

        PATTERN = /\A(\p{L}|_)(\p{L}|\p{N}|[.\-_])*\z/

        pattern PATTERN

        def self.default_xsd_type
          "xs:string"
        end
      end
    end
  end
end
