# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        # Represents a single entry in the type index for serialization
        class TypeIndexEntry < Lutaml::Model::Serializable
          attribute :clark_key, :string
          attribute :type_category, :string
          attribute :namespace, :string
          attribute :local_name, :string
          attribute :schema_file, :string

          yaml do
            map "clark_key", to: :clark_key
            map "type_category", to: :type_category
            map "namespace", to: :namespace
            map "local_name", to: :local_name
            map "schema_file", to: :schema_file
          end

          # Create from type index info hash
          # @param clark_key [String] Clark notation key
          # @param info [Hash] Type information hash
          # @return [TypeIndexEntry]
          def self.from_index_info(clark_key, info)
            new(
              clark_key: clark_key,
              type_category: info[:type].to_s,
              namespace: info[:namespace],
              local_name: info[:definition]&.name,
              schema_file: info[:schema_file],
            )
          end
        end
      end
    end
  end
end
