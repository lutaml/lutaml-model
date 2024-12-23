module Lutaml
  module Model
    module Type
      class Hash < Value
        def self.cast(value)
          return nil if value.nil?

          hash = if value.respond_to?(:to_h)
                   value.to_h
                 else
                   Hash(value)
                 end

          normalize_hash(hash)
        end

        def self.normalize_hash(hash)
          return hash["text"] if hash.keys == ["text"]

          hash = hash.to_h if hash.is_a?(Lutaml::Model::MappingHash)

          normalized_hash = hash.transform_values do |value|
            normalize_value(value)
          end

          normalized_hash["elements"] || normalized_hash
        end

        def self.normalize_value(value)
          return value unless value.is_a?(::Hash)

          nested = normalize_hash(value)
          nested.is_a?(::Hash) ? nested.except("text") : nested
        end

        def self.serialize(value)
          return nil if value.nil?
          return value if value.is_a?(Hash)

          value.respond_to?(:to_h) ? value.to_h : Hash(value)
        end

        # Format-specific serialization methods
        def to_xml
          value
        end

        def to_json(*_args)
          value
        end

        def to_yaml
          value
        end

        def to_toml
          value
        end
      end
    end
  end
end
