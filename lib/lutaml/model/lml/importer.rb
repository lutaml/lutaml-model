# frozen_string_literal: true

require "json"
require "strscan"
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
          classes = Materialization.build(tree, namespace: nil,
                                                type_bindings: type_bindings)
          return MappingCompiler.apply(classes, tree) unless namespace

          install_and_compile(classes, tree, namespace)
        end

        # All or nothing: the constants are installed once every class is
        # built and linked (the mapping compiler resolves polymorphic
        # targets by constant name, so it runs after) and are removed
        # again if the mapping compile refuses, so a retry starts clean.
        def self.install_and_compile(classes, tree, namespace)
          installation = Materialization.install(classes, tree["models"], namespace)
          completed = false
          result = MappingCompiler.apply(classes, tree)
          completed = true
          result
        ensure
          installation&.rollback unless completed
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

        # Rejects an object that repeats a key. The json gem's own
        # behaviour differs by version (older ones keep the last value
        # silently, some object_class paths skip the check), so this walks
        # the text itself: strings are tokenised with escapes, keys are
        # compared after decoding, and malformed text is left to
        # JSON.parse to refuse.
        def self.reject_duplicate_keys!(text)
          scanner = StringScanner.new(text)
          stack = []
          until scanner.eos?
            if scanner.skip(/\s+/) then next
            elsif (token = scanner.scan(/"(?:[^"\\]|\\.)*"/m))
              note_string(stack, token)
            elsif scanner.skip(/\{/) then stack.push({ keys: {}, expect_key: true })
            elsif scanner.skip(/\[/) then stack.push(nil)
            elsif scanner.skip(/[}\]]/) then stack.pop
            elsif scanner.skip(/,/) then stack.last[:expect_key] = true if stack.last
            elsif scanner.skip(/[^\s,:\[\]{}"]+|:|"/) then next
            end
          end
        end

        def self.note_string(stack, token)
          frame = stack.last
          return unless frame && frame[:expect_key]

          frame[:expect_key] = false
          key = JSON.parse(token)
          if frame[:keys].key?(key)
            raise RejectedError.new(:invalid_document, "bundle", "duplicate key #{key.inspect}")
          end

          frame[:keys][key] = true
        rescue JSON::ParserError
          nil
        end

        def self.parse(text)
          reject_duplicate_keys!(text)
          JSON.parse(text, max_nesting: DocumentValidator::MAX_DEPTH)
        rescue JSON::ParserError => e
          raise RejectedError.new(:invalid_document, "bundle", "not valid JSON: #{e.message.lines.first.to_s.strip}")
        end

        private_class_method :validate, :parse, :install_and_compile,
                             :reject_duplicate_keys!, :note_string
      end
    end
  end
end
