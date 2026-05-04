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
end
