# frozen_string_literal: true

module Lutaml
  module Model
    module Lml
      autoload :Document, "#{__dir__}/lml/document"
      autoload :Exporter, "#{__dir__}/lml/exporter"
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
    end
  end
end
