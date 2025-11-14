require_relative "string"
require "uri"

module Lutaml
  module Model
    module Type
      # URI type for xs:anyURI
      #
      # Validates and handles URI values.
      #
      # @example Using URI type
      #   attribute :homepage, :uri
      class Uri < String
        def self.cast(value, _options = {})
          return nil if value.nil?
          return value if value.is_a?(::URI)
          return value if value.is_a?(::String)

          value.to_s
        end

        def self.serialize(value)
          return nil if value.nil?
          return value.to_s if value.is_a?(::URI)

          value.to_s
        end

        # XSD type for Uri
        #
        # @return [String] xs:anyURI
        def self.xsd_type
          "xs:anyURI"
        end

        # Validate URI format
        #
        # @param value [String] the URI to validate
        # @return [Boolean] true if valid URI format
        def self.valid_uri?(value)
          ::URI.parse(value.to_s)
          true
        rescue ::URI::InvalidURIError
          false
        end
      end
    end
  end
end