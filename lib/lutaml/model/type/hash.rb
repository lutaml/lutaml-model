# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class Hash < Value
        def self.cast(value)
          return super if Utils.uninitialized?(value)
          return nil if value.nil?

          hash = case value
                 when ::Hash then value
                 when ::Array then value.to_h
                 else value.to_h
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
          return value if value.is_a?(::Hash)

          case value
          when ::Hash then value
          when ::Array then value.to_h
          else value.to_h
          end
        end

        # XSD type for Hash
        #
        # @return [String] xs:anyType
        def self.default_xsd_type
          "xs:anyType"
        end
      end
    end
  end
end
