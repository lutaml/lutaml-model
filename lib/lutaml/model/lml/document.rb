# frozen_string_literal: true

module Lutaml
  module Model
    module Lml
      # The neutral LML document: a model class's declarations as a
      # plain hash with a canonical render and a sha256 checksum. The
      # hash layout is 1:1 with the declaration vocabulary so the
      # round-trip gate (export → canonical render → checksum) is the
      # design's spine.
      class Document
        LML_VERSION = 1

        attr_reader :model_name, :attributes, :mappings, :register

        def initialize(model_name:, attributes:, mappings:, register: nil)
          @model_name = model_name
          @attributes = attributes
          @mappings = mappings
          @register = register
        end

        def self.from_hash(hash)
          raise ArgumentError, "missing model name" unless hash["model"]

          new(
            model_name: hash["model"],
            attributes: hash["attributes"] || [],
            mappings: hash["mappings"] || {},
            register: hash["register"],
          )
        end

        def to_h
          {
            "lml" => LML_VERSION,
            "model" => model_name,
            "register" => register,
            "attributes" => attributes,
            "mappings" => mappings,
          }.compact
        end

        def to_json(*)
          require "json"
          JSON.generate(to_h)
        end

        def to_yaml
          require "yaml"
          YAML.safe_dump(
            deep_stringify_keys(to_h),
            permitted_classes: [],
            aliases: false,
            sort_keys: false,
            line_width: -1,
          )
        end

        # The canonical form: the document hash with sorted keys at
        # every level, serialized deterministically. The checksum is
        # pinned over this form — equal checksums mean equal
        # declarations, independent of key order or format.
        def canonical_json
          require "json"
          JSON.generate(canonicalize(to_h))
        end

        def checksum
          require "digest"
          "sha256:#{Digest::SHA256.hexdigest(canonical_json)}"
        end

        def ==(other)
          other.is_a?(Document) && canonical_json == other.canonical_json
        end
        alias eql? ==

        def hash
          canonical_json.hash
        end

        private

        def canonicalize(node)
          case node
          when Hash
            node.keys.sort_by(&:to_s).to_h { |key| [key.to_s, canonicalize(node[key])] }
          when Array
            node.map { |item| canonicalize(item) }
          else
            node
          end
        end

        def deep_stringify_keys(node)
          case node
          when Hash
            node.to_h { |key, value| [key.to_s, deep_stringify_keys(value)] }
          when Array
            node.map { |item| deep_stringify_keys(item) }
          else
            node
          end
        end
      end
    end
  end
end
