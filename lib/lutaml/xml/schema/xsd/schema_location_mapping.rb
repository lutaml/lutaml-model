# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        # Represents a schema location mapping for resolving import/include paths
        class SchemaLocationMapping < Lutaml::Model::Serializable
          # The source pattern to match (can be string or regex pattern)
          attribute :from, :string

          # The target path to map to
          attribute :to, :string

          # Flag indicating if 'from' is a regex pattern
          attribute :pattern, :boolean, default: -> { false }

          yaml do
            map "from", to: :from
            map "to", to: :to
            map "pattern", to: :pattern
          end

          # Override initialize to auto-detect Regexp patterns
          # Supports both hash argument (for Lutaml::Model) and keyword arguments
          # @param attributes [Hash] Attributes hash (for deserialization)
          # @param from [String, Regexp] The source pattern
          # @param to [String] The target path
          # @param pattern [Boolean, nil] Explicit pattern flag (optional)
          def initialize(attributes = nil, from: nil, to: nil, pattern: nil,
      **)
            # Handle hash argument from Lutaml::Model deserialization
            if attributes.is_a?(Hash)
              from = attributes[:from] || attributes["from"]
              to = attributes[:to] || attributes["to"]
              pattern = attributes[:pattern] || attributes["pattern"]
            end

            # Auto-detect if from is a Regexp
            detected_pattern = from.is_a?(Regexp)

            # Convert Regexp to source string for storage
            from_str = detected_pattern ? from.source : from

            # Use explicit pattern flag if provided, otherwise use detected value
            final_pattern = pattern.nil? ? detected_pattern : pattern

            super(from: from_str, to: to, pattern: final_pattern, **)
          end

          # Convert hash-based mapping to SchemaLocationMapping instance
          # @param mapping [Hash] Hash with :from/:to or "from"/"to" keys
          # @return [SchemaLocationMapping]
          def self.from_hash(mapping)
            from = mapping[:from] || mapping["from"]
            to = mapping[:to] || mapping["to"]
            pattern = mapping[:pattern] || mapping["pattern"]

            new(from: from, to: to, pattern: pattern)
          end

          # Convert to hash format compatible with Glob.schema_mappings
          # @return [Hash]
          def to_glob_format
            {
              from: pattern ? Regexp.new(from) : from,
              to: to,
            }
          end
        end
      end
    end
  end
end
