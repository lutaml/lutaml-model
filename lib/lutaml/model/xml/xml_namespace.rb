# frozen_striing_literal: true

module Lutaml
  module Model
    module Xml
      class XmlNamespace
        # Return name
        #
        # @return [String]
        #
        # @api private
        attr_accessor :uri

        # Return prefix
        #
        # @return [String]
        #
        # @api private
        attr_accessor :prefix

        # Initialize instance
        #
        # @param [String, nil] name
        # @param [String, nil] prefix
        #
        # @api private
        def initialize(uri = nil, prefix = nil)
          @uri = uri
          @prefix = normalize_prefix(prefix)
        end

        # Generate unique key for this namespace configuration
        #
        # The key is based on prefix and URI, ensuring that same config = same key.
        # This enables proper deduplication and lookup in hash structures.
        #
        # @return [String] unique key in format "prefix:uri" or ":uri" for default
        #
        # @api private
        def self.to_key
          prefix = prefix_default
          uri = self.uri

          if prefix && !prefix.empty?
            "#{prefix}:#{uri}"
          else
            ":#{uri}"
          end
        end

        def normalize_prefix(prefix)
          normalized_prefix = prefix.to_s.gsub(/xmlns:?/, "")
          return if normalized_prefix.empty?

          normalized_prefix
        end

        def attr_name
          if Utils.present?(prefix)
            "xmlns:#{prefix}"
          else
            "xmlns"
          end
        end
      end
    end
  end
end
