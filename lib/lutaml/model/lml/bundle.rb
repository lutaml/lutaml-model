# frozen_string_literal: true

require "json"
require "digest"
require_relative "rejected_error"

module Lutaml
  module Model
    module Lml
      # An immutable version-1 LML bundle: a closed graph of v2 model
      # documents keyed by stable "Model@register" IDs. Construction
      # normalises ordering (models/value_types key-sorted, roots and
      # capabilities sorted unique) and deep-freezes a private copy, so a
      # caller mutating its input cannot change a pinned identity.
      class Bundle
        BUNDLE_VERSION = 1

        attr_reader :roots, :models, :value_types, :capabilities, :provenance

        def initialize(roots:, models:, value_types: {}, capabilities: nil,
                       provenance: nil)
          @models = freeze_tree(sort_keys(stringify(models)))
          @value_types = freeze_tree(sort_keys(stringify(value_types)))
          @roots = roots.map(&:to_s).uniq.sort.freeze
          @capabilities = (capabilities || derive_capabilities).map(&:to_s)
            .uniq.sort.freeze
          @provenance = provenance && freeze_tree(stringify(provenance))
          freeze
        end

        def to_h
          {
            "lml_bundle" => BUNDLE_VERSION,
            "roots" => roots,
            "models" => models,
            "value_types" => value_types,
            "capabilities" => capabilities,
            "provenance" => provenance,
          }.compact
        end

        # Recursively key-sorted compact UTF-8 JSON (no BOM, no trailing
        # newline; "/" and non-ASCII are not escaped).
        def canonical_json(include_provenance: true)
          hash = to_h
          hash = hash.except("provenance") unless include_provenance
          JSON.generate(canonicalize(hash))
        end

        # Semantic identity: provenance is excluded.
        def checksum
          "sha256:#{Digest::SHA256.hexdigest(canonical_json(include_provenance: false))}"
        end

        # Checksum of one full model document.
        def model_checksum(id)
          model = models.fetch(id.to_s)
          "sha256:#{Digest::SHA256.hexdigest(JSON.generate(canonicalize(model)))}"
        end

        def ==(other)
          other.is_a?(Bundle) && canonical_json == other.canonical_json
        end
        alias eql? ==

        def hash
          canonical_json.hash
        end

        private

        def derive_capabilities
          models.values.flat_map { |doc| (doc["mappings"] || {}).keys }
        end

        def stringify(node)
          case node
          when ::Hash then node.to_h { |k, v| [k.to_s, stringify(v)] }
          when Array then node.map { |item| stringify(item) }
          else node
          end
        end

        def sort_keys(hash)
          hash.sort_by { |key, _| key }.to_h
        end

        def canonicalize(node)
          case node
          when ::Hash
            node.sort_by { |key, _| key.to_s }
              .to_h { |key, value| [key.to_s, canonicalize(value)] }
          when Array then node.map { |item| canonicalize(item) }
          else node
          end
        end

        def freeze_tree(node)
          case node
          when ::Hash
            node.each_value { |value| freeze_tree(value) }
            node.each_key(&:freeze)
          when Array then node.each { |item| freeze_tree(item) }
          when ::String then node.freeze
          end
          node.freeze
        end
      end
    end
  end
end
