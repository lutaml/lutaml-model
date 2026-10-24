# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema email-address datatype (#107): a string containing
      # an at-sign, per the metaschema-datatypes pattern `.+@.+`.
      #
      # @example Using EmailAddress type
      #   attribute :contact, :email_address
      class EmailAddress < String
        extend MetaschemaPattern

        PATTERN = /\A.+@.+\z/

        pattern PATTERN

        def self.json_schema_format
          "email"
        end

        def self.default_xsd_type
          "xs:string"
        end
      end
    end
  end
end
