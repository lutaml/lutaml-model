# frozen_string_literal: true

module Lutaml
  module Model
    module Lml
      autoload :ArtifactVerifier, "#{__dir__}/lml/artifact_verifier"
      autoload :Bundle, "#{__dir__}/lml/bundle"
      autoload :Document, "#{__dir__}/lml/document"
      autoload :DocumentValidator, "#{__dir__}/lml/document_validator"
      autoload :Exporter, "#{__dir__}/lml/exporter"
      autoload :GraphExporter, "#{__dir__}/lml/graph_exporter"
      autoload :Importer, "#{__dir__}/lml/importer"
      autoload :MappingCompiler, "#{__dir__}/lml/mapping_compiler"
      autoload :Materialization, "#{__dir__}/lml/materialization"
      autoload :OrderedContent, "#{__dir__}/lml/ordered_content"
      autoload :RejectedError, "#{__dir__}/lml/rejected_error"
      autoload :RoundTrip, "#{__dir__}/lml/round_trip"

      module_function

      # Export a model class's declarations to a neutral LML document
      # (lutaml-model#1033 Phase 1).
      #
      # The document is the model's `attribute` + per-format mapping
      # vocabulary, serialized with sorted keys and pinned by a sha256
      # checksum over the canonical form — the same
      # "declare once, verify everywhere" move PARG made for grammars.
      #
      # Constructor-contract constructs are rejected with named errors
      # (RejectedError): lambda defaults, custom `initialize` bodies,
      # imperative element-order mixes.
      #
      # @param klass [Class] a Serializable model class
      # @param register [Symbol, nil] the register context
      # @return [Lml::Document]
      def export(klass, register: nil)
        Exporter.export(klass, register: register)
      end

      # The round-trip gate: re-export the model from the document's
      # recorded model name and compare canonical forms — identical
      # declarations, identical checksum.
      def verify(document, register: nil)
        RoundTrip.verify(document, register: register)
      end

      # Export the closed graph of models reachable from +roots+ as an
      # immutable neutral Bundle of v2 documents keyed by "Model@register".
      #
      # @param roots [Class, Array<Class, Array(Class, String)>] classes,
      #   or [class, register] pairs
      # @param register [Symbol, String, nil] default register for roots
      #   without one; nil resolves through the model's own default
      # @param provenance [Hash, nil] recorded but excluded from the checksum
      # @return [Lml::Bundle]
      def export_bundle(roots, register: nil, provenance: nil)
        GraphExporter.export(
          roots,
          projector: ->(klass, reg) { Exporter.project(klass, register: reg.to_s == "default" ? nil : reg.to_sym) },
          register: register, provenance: provenance
        )
      end

      # Build fresh Ruby classes (attributes and xml/json/yaml mappings)
      # from a bundle, without the source constants.
      #
      # @param bundle [Lml::Bundle, Hash, String] bundle, Hash or JSON text
      # @param namespace [Module, nil] named holder for generated
      #   constants (required when the bundle declares polymorphism)
      # @param type_bindings [Hash{String=>Class}] trusted value types
      # @return [Hash{String=>Class}] model id => generated class
      def import_bundle(bundle, namespace: nil, type_bindings: {})
        Importer.import(bundle, namespace: namespace, type_bindings: type_bindings)
      end

      # The reconstruction gate: import the bundle, export the generated
      # classes and require identical declarations and checksum.
      # @return [Lml::Bundle] the re-exported bundle
      # @raise [Lml::RejectedError] :round_trip_mismatch on drift
      def verify_materialization(bundle, namespace: nil, type_bindings: {})
        RoundTrip.verify_materialization(bundle, namespace: namespace, type_bindings: type_bindings)
      end
    end
  end
end
