# frozen_string_literal: true

require "json"
require_relative "bundle"
require_relative "document_validator"
require_relative "materialization"
require_relative "mapping_compiler"

module Lutaml
  module Model
    module Lml
      # Imports a neutral LML bundle into a fresh Ruby declaration graph
      # (lutaml-model#1033, card 03c): validate, allocate and link the
      # attributes (Materialization), then declare the xml/json/yaml
      # mappings (MappingCompiler). Nothing is evaluated from the
      # document, and the source constants are never consulted.
      class Importer
        # @param source [Bundle, Hash, String] a bundle, its Hash form
        #   (string or symbol keys) or its JSON text
        # @param namespace [Module, nil] named holder for the generated
        #   constants. Polymorphic discriminator targets are resolved by
        #   Ruby through Object.const_get, so a bundle that declares
        #   polymorphism needs a named (installed) namespace.
        # @param type_bindings [Hash{String=>Class}] trusted classes by
        #   value-type id
        # @return [Hash{String=>Class}] model id => generated class
        def self.import(source, namespace: nil, type_bindings: {})
          tree = validate(source)
          classes = Materialization.build(tree, namespace: namespace,
                                                type_bindings: type_bindings)
          MappingCompiler.apply(classes, tree)
        end

        # The validated, immutable form of any accepted bundle source.
        # @return [Bundle]
        def self.bundle(source)
          return source if source.is_a?(Bundle)

          tree = validate(source)
          Bundle.new(roots: tree["roots"], models: tree["models"],
                     value_types: tree["value_types"] || {},
                     capabilities: tree["capabilities"],
                     provenance: tree["provenance"])
        end

        def self.validate(source)
          hash = case source
                 when Bundle then source.to_h
                 when ::String then parse(source)
                 else source
                 end
          DocumentValidator.validate!(hash, kind: :bundle)
        end

        def self.parse(text)
          JSON.parse(text)
        rescue JSON::ParserError => e
          raise RejectedError.new(:invalid_document, "bundle", "not valid JSON: #{e.message.lines.first.to_s.strip}")
        end

        private_class_method :validate, :parse
      end
    end
  end
end
