# frozen_string_literal: true

require_relative "rejected_error"
require_relative "document_validator"

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

        attr_reader :model_name, :attributes, :mappings, :register, :version

        def initialize(model_name:, attributes:, mappings:, register: nil,
                       version: LML_VERSION, extras: {})
          @model_name = model_name
          @attributes = attributes
          @mappings = mappings
          @register = register
          @version = version
          @extras = extras
        end

        # Validates against the contract and keeps the supplied version:
        # v1 documents stay v1 (same canonical form and checksum); v2
        # documents keep every declared member. An unsupported version
        # or malformed document raises RejectedError, never a rewrite.
        def self.from_hash(hash)
          tree = DocumentValidator.validate!(hash, kind: :document)
          if tree["lml"] == LML_VERSION
            return new(
              model_name: tree["model"],
              attributes: tree["attributes"] || [],
              mappings: tree["mappings"] || {},
              register: tree["register"],
            )
          end

          new(
            model_name: tree["model"],
            attributes: tree["attributes"],
            mappings: tree["mappings"],
            register: tree["register"],
            version: tree["lml"],
            extras: tree.slice("ordered_content"),
          )
        end

        def to_h
          {
            "lml" => version,
            "model" => model_name,
            "register" => register,
            "attributes" => attributes,
            "mappings" => mappings,
          }.merge(@extras).compact
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
          JSON.generate(version == LML_VERSION ? canonicalize(to_h) : canonicalize_sorted(to_h))
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

        # v1 identity is frozen: inside Lutaml::Model the bare `Hash` below
        # resolves to Lutaml::Model::Hash, so this never sorts plain hashes
        # and v1 canonical form keeps the export's insertion order. Existing
        # v1 checksums depend on that, so it must not change.
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

        # v2 canonical form: recursively key-sorted, array order kept.
        def canonicalize_sorted(node)
          case node
          when ::Hash
            node.keys.sort.to_h { |key| [key, canonicalize_sorted(node[key])] }
          when ::Array
            node.map { |item| canonicalize_sorted(item) }
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
