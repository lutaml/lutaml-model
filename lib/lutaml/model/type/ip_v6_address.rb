# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # NIST Metaschema ip-v6-address datatype (#107): RFC3513 IPv6 text
      # form, per the metaschema-datatypes pattern (the generalized
      # StackOverflow IPv6 expression with metaschema customizations,
      # including link-local zones and embedded IPv4).
      #
      # @example Using IpV6Address type
      #   attribute :address, :ip_v6_address
      class IpV6Address < String
        extend MetaschemaPattern

        HEX4 = "[0-9a-fA-F]{1,4}"
        OCTET = "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])"
        EMBEDDED_V4 = "(#{OCTET}\\.){3,3}#{OCTET}".freeze
        PATTERN = /
          \A(
            (#{HEX4}:){7,7}#{HEX4}
            |([0-9a-fA-F]{1,4}:){1,7}:
            |([0-9a-fA-F]{1,4}:){1,6}:#{HEX4}
            |([0-9a-fA-F]{1,4}:){1,5}(:#{HEX4}){1,2}
            |([0-9a-fA-F]{1,4}:){1,4}(:#{HEX4}){1,3}
            |([0-9a-fA-F]{1,4}:){1,3}(:#{HEX4}){1,4}
            |([0-9a-fA-F]{1,4}:){1,2}(:#{HEX4}){1,5}
            |#{HEX4}:((:#{HEX4}){1,6})
            |:((:#{HEX4}){1,7}|:)
            |[fF][eE]80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}
            |::([fF]{4}(:0{1,4}){0,1}:){0,1}#{EMBEDDED_V4}
            |([0-9a-fA-F]{1,4}:){1,4}:#{EMBEDDED_V4}
          )\z
        /x

        def self.default_xsd_type
          "xs:string"
        end
      end
    end
  end
end
