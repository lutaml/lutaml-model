# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema hostname datatype (#107): a non-empty string with
      # no outer whitespace. The normative XSD carries no hostname pattern
      # yet (the metaschema spec notes it is pending), so only the
      # trimmed-string base constraint applies.
      #
      # @example Using Hostname type
      #   attribute :host, :hostname
      class Hostname < String
        extend MetaschemaPattern

        PATTERN = /\A\S(.*\S)?\z/

        pattern PATTERN

        def self.default_xsd_type
          "xs:string"
        end
      end
    end
  end
end
