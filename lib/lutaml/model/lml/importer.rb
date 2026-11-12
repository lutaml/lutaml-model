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
        # A bounded run of string body (plain characters and escapes). The
        # repetition cap keeps a JavaScript regexp engine from recursing
        # once per escape on a huge string (Opal); the caller loops over runs.
        STRING_RUN = /[^"\\]*(?:\\.[^"\\]*){0,1000}/m
        private_constant :STRING_RUN

        # @param source [Bundle, Hash, String] a bundle, its Hash form
        #   (string keys; symbol keys are refused) or its JSON text
        # @param namespace [Module, nil] unfrozen, named holder for the generated
        #   constants. Polymorphic discriminator targets are resolved by
        #   Ruby through Object.const_get, so a bundle that declares
        #   polymorphism needs a named (installed) namespace.
        # @param type_bindings [Hash{String=>Class}] trusted classes by
        #   value-type id
        # @return [Hash{String=>Class}] model id => generated class
        def self.import(source, namespace: nil, type_bindings: {})
          check_namespace!(namespace)
          tree = validate(source)
          classes = Materialization.build(tree, namespace: nil,
                                                type_bindings: type_bindings)
          return MappingCompiler.apply(classes, tree) unless namespace

          install_and_compile(classes, tree, namespace)
        rescue RejectedError => e
          raise e.as_import
        end

        def self.check_namespace!(namespace)
          return if namespace.nil? || (namespace.is_a?(::Module) && !namespace.frozen?)

          raise RejectedError.new(:invalid_document, nil, "namespace must be an unfrozen Module",
                                  import: true)
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
        rescue RejectedError => e
          raise e.as_import
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
        # compared after decoding. Malformed text (an unterminated string,
        # nesting past the cap) stops the walk at once and is left to
        # JSON.parse to refuse, which keeps the scan linear.
        def self.reject_duplicate_keys!(text)
          scanner = StringScanner.new(text)
          stack = []
          until scanner.eos?
            if scanner.skip(/\s+/) then next
            elsif scanner.check(%r{/}) then reject_comment!
            elsif scanner.check(/"/)
              token = scan_string(scanner) or return
              note_string(stack, token)
            elsif scanner.skip(/\{/)
              return if stack.size >= DocumentValidator::MAX_DEPTH

              stack.push({ keys: {}, expect_key: true })
            elsif scanner.skip(/\[/)
              return if stack.size >= DocumentValidator::MAX_DEPTH

              stack.push(nil)
            elsif scanner.skip(/[}\]]/) then stack.pop
            elsif scanner.skip(/,/) then stack.last[:expect_key] = true if stack.last
            elsif (bare = scanner.scan(/[^\s,:\[\]{}"]+|:/))
              reject_comment! if bare.include?("/")
            end
          end
        end

        # The next string token, quotes included, or nil when it is
        # unterminated (a lone trailing backslash or the end of the text).
        def self.scan_string(scanner)
          token = scanner.scan('"')
          loop do
            run = scanner.scan(STRING_RUN)
            token << run
            return token << scanner.scan('"') if scanner.check(/"/)
            return nil if run.empty?
          end
        end

        # JSON has no comments. Older json gems accept them and newer ones
        # do not, and a comment can hide a quote from this scanner, so they
        # are refused outright and behaviour is the same on every json.
        def self.reject_comment!
          raise RejectedError.new(:invalid_document, nil, "not valid JSON: comments are not allowed",
                                  import: true)
        end

        def self.note_string(stack, token)
          frame = stack.last
          return unless frame && frame[:expect_key]

          frame[:expect_key] = false
          key = JSON.parse(token)
          if frame[:keys].key?(key)
            raise RejectedError.new(:invalid_document, "bundle", "duplicate key #{RejectedError.show(key)}", import: true)
          end

          frame[:keys][key] = true
        rescue JSON::ParserError
          nil
        end

        def self.parse(text)
          text = utf8_text(text)
          reject_duplicate_keys!(text)
          JSON.parse(text, max_nesting: DocumentValidator::MAX_DEPTH)
        rescue JSON::ParserError => e
          raise RejectedError.new(:invalid_document, "bundle", "not valid JSON: #{e.message.lines.first.to_s.strip}",
                                  import: true)
        end

        def self.utf8_text(text)
          text = text.dup.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::BINARY
          return text if text.encoding.ascii_compatible? && text.valid_encoding?

          raise RejectedError.new(:invalid_document, nil, "not valid JSON: text is not valid UTF-8",
                                  import: true)
        end

        private_class_method :validate, :parse, :install_and_compile,
                             :reject_duplicate_keys!, :note_string, :scan_string, :check_namespace!,
                             :reject_comment!, :utf8_text
      end
    end
  end
end
