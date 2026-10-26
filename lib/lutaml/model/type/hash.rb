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
          xml = hash.is_a?(Lutaml::Model::MappingHash)
          return hash["text"] if text_node?(hash)

          hash = hash.to_h if xml

          normalized = hash.transform_values do |value|
            normalize_value(value)
          end
          xml ? (normalized["elements"] || normalized) : normalized
        end

        # {"text" => string} is the XML text-node convention and
        # collapses to the string. Any other "text" key — structured
        # values, or appearing alongside other keys in non-XML data —
        # is ordinary data and must round-trip verbatim
        # (lutaml/lutaml-model#1013).
        def self.text_node?(hash)
          # ::String — unqualified String resolves to Type::String here
          hash.is_a?(::Hash) && hash.keys == ["text"] &&
            hash["text"].is_a?(::String)
        end

        def self.normalize_value(value)
          return value unless value.is_a?(::Hash)

          nested = normalize_hash(value)
          if value.is_a?(Lutaml::Model::MappingHash) && nested.is_a?(::Hash)
            nested.except("text")
          else
            nested
          end
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
