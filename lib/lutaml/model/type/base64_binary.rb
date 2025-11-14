require_relative "string"
require "base64"

module Lutaml
  module Model
    module Type
      # Base64Binary type for xs:base64Binary
      #
      # Handles base64 encoding/decoding of binary data
      #
      # @example Using Base64Binary type
      #   attribute :attachment, :base64_binary
      class Base64Binary < String
        def self.cast(value, _options = {})
          return nil if value.nil?
          return value if value.is_a?(::String)

          value.to_s
        end

        def self.serialize(value)
          return nil if value.nil?

          value.to_s
        end

        # XSD type for Base64Binary
        #
        # @return [String] xs:base64Binary
        def self.xsd_type
          "xs:base64Binary"
        end

        # Encode binary data to base64
        #
        # @param data [String] binary data to encode
        # @return [String] base64 encoded string
        def self.encode(data)
          return nil if data.nil?

          Base64.strict_encode64(data)
        end

        # Decode base64 to binary data
        #
        # @param encoded [String] base64 encoded string
        # @return [String] decoded binary data
        def self.decode(encoded)
          return nil if encoded.nil?

          Base64.strict_decode64(encoded)
        end
      end
    end
  end
end
