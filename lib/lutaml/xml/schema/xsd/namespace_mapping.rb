# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        # Represents a namespace prefix to URI mapping
        class NamespaceMapping < Lutaml::Model::Serializable
          # The namespace prefix (e.g., "gml", "xs")
          attribute :prefix, :string

          # The namespace URI (e.g., "http://www.opengis.net/gml/3.2")
          attribute :uri, :string

          yaml do
            map "prefix", to: :prefix
            map "uri", to: :uri
          end

          # Create from a hash entry
          # @param prefix [String] The namespace prefix
          # @param uri [String] The namespace URI
          # @return [NamespaceMapping]
          def self.from_pair(prefix, uri)
            new(prefix: prefix, uri: uri)
          end

          # Convert to hash format
          # @return [Hash]
          def to_hash
            { prefix => uri }
          end
        end
      end
    end
  end
end
