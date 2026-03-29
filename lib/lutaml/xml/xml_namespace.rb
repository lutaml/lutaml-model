# frozen_striing_literal: true

module Lutaml
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
        # Only strip "xmlns:" prefix (e.g., "xmlns:foo" → "foo").
        # Do NOT strip "xmlns" from prefixes like "xmlns_1.0" (valid NCName).
        # Bare "xmlns" (no colon) represents the default namespace → return nil.
        prefix_str = prefix.to_s
        return nil if prefix_str == "xmlns"

        normalized_prefix = prefix_str.sub(/^xmlns:/, "")
        return if normalized_prefix.empty?

        normalized_prefix
      end

      def attr_name
        if ::Lutaml::Model::Utils.present?(prefix)
          "xmlns:#{prefix}"
        else
          "xmlns"
        end
      end
    end
  end
end
