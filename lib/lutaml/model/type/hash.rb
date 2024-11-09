module Lutaml
  module Model
    module Type
      class Hash < Value
        def self.cast(value)
          return nil if value.nil?
          hash = Hash(value)
          normalize_hash(hash)
        end

        def self.serialize(value)
          return nil if value.nil?
          return value.to_h if value.respond_to?(:to_h)
          Hash(value)
        end

        def self.normalize_hash(hash)
          return hash["text"] if hash.keys == ["text"]

          hash = hash.to_h if hash.is_a?(Lutaml::Model::MappingHash)

          hash.filter_map do |key, value|
            next if key == "text"

            if value.is_a?(::Hash)
              [key, normalize_hash(value)]
            else
              [key, value]
            end
          end.to_h
        end
      end

      register(:hash, ::Lutaml::Model::Type::Hash)
    end
  end
end
