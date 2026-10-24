# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema uri-reference datatype (#107): a relative or
      # absolute URI reference — any non-empty string without outer
      # whitespace, unlike :uri which requires a scheme.
      #
      # @example Using UriReference type
      #   attribute :link, :uri_reference
      class UriReference < String
        extend MetaschemaPattern

        PATTERN = /\A\S(.*\S)?\z/

        pattern PATTERN

        def self.default_xsd_type
          "xs:anyURI"
        end
      end
    end
  end
end
