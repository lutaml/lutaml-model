require_relative "string"

module Lutaml
  module Model
    module Type
      # HexBinary type for xs:hexBinary
      #
      # Handles hexadecimal encoding/decoding of binary data
      #
      # @example Using HexBinary type
      #   attribute :checksum, :hex_binary
      class HexBinary < String
        def self.cast(value, _options = {})
          return nil if value.nil?
          return value if value.is_a?(::String)

          value.to_s
        end

        def self.serialize(value)
          return nil if value.nil?

          value.to_s
        end

        # XSD type for HexBinary
        #
        # @return [String] xs:hexBinary
        def self.xsd_type
          "xs:hexBinary"
        end

        # Encode binary data to hex
        #
        # @param data [String] binary data to encode
        # @return [String] hex encoded string
        def self.encode(data)
          return nil if data.nil?

          data.unpack1("H*")
        end

        # Decode hex to binary data
        #
        # @param encoded [String] hex encoded string
        # @return [String] decoded binary data
        def self.decode(encoded)
          return nil if encoded.nil?

          [encoded].pack("H*")
        end
      end
    end
  end
end
