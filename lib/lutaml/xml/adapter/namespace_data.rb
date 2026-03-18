# frozen_string_literal: true

module Lutaml
  module Xml
    module Adapter
      # Simple data class for holding namespace URI and prefix pairs
      # during XML parsing and serialization.
      #
      # This is an internal class used by XML adapters. For defining
      # custom namespaces, use Lutaml::Xml::Namespace instead.
      #
      # @api private
      class NamespaceData
        # Return URI
        #
        # @return [String]
        attr_accessor :uri

        # Return prefix
        #
        # @return [String]
        attr_accessor :prefix

        # Initialize instance
        #
        # @param uri [String, nil] the namespace URI
        # @param prefix [String, nil] the namespace prefix
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
          if ::Lutaml::Model::Utils.present?(prefix)
            "xmlns:#{prefix}"
          else
            "xmlns"
          end
        end
      end
    end
  end
end
