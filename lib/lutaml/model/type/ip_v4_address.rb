# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema ip-v4-address datatype (#107): dotted-quad IPv4
      # per the metaschema-datatypes pattern.
      #
      # @example Using IpV4Address type
      #   attribute :address, :ip_v4_address
      class IpV4Address < String
        extend MetaschemaPattern

        OCTET = /(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])/
        PATTERN = /\A#{OCTET.source}\.#{OCTET.source}\.#{OCTET.source}\.#{OCTET.source}\z/

        def self.json_schema_format
          "ipv4"
        end

        def self.default_xsd_type
          "xs:string"
        end
      end
    end
  end
end
