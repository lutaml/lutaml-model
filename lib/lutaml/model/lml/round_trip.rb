# frozen_string_literal: true

module Lutaml
  module Model
    module Lml
      # The round-trip gate: the document must re-derive the model it
      # came from. Phase 1's importer-side is a re-export comparison —
      # the recorded model is re-read and re-projected, and the
      # canonical forms must be identical (equal checksums). 1:1-ness
      # is the design's spine; a drift here means the document lost a
      # declaration on the way out.
      #
      # `verify_materialization` is the bundle-level gate: it imports a
      # bundle into fresh classes (no source constants), exports those
      # classes again and requires the same declarations and checksum.
      class RoundTrip
        def self.verify(document, register: nil)
          new(document, register: register).verify
        end

        # @param source [Bundle, Hash, String] the bundle to reconstruct
        # @param namespace [Module, nil] named holder for the generated
        #   classes; nil uses a transient one removed afterwards
        # @param type_bindings [Hash{String=>Class}] trusted value types
        # @return [Bundle] the re-exported bundle, equal to the input
        # @raise [RejectedError] :round_trip_mismatch when it differs
        def self.verify_materialization(source, namespace: nil, type_bindings: {})
          expected = Importer.bundle(source)
          return reconstruct(expected, namespace, type_bindings) if namespace

          holder_name = "LmlVerify#{object_id.abs}#{Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)}"
          holder = Module.new
          Object.const_set(holder_name, holder)
          begin
            reconstruct(expected, holder, type_bindings)
          ensure
            Object.send(:remove_const, holder_name)
          end
        end

        def self.reconstruct(expected, namespace, type_bindings)
          classes = Importer.import(expected, namespace: namespace, type_bindings: type_bindings)
          actual = reexport(expected, classes)
          return actual if actual == expected

          raise RejectedError.new(:round_trip_mismatch, expected.roots.join(", "),
                                  "the bundle does not re-derive from its materialization " \
                                  "(#{expected.checksum.slice(0, 20)} vs #{actual.checksum.slice(0, 20)})")
        end

        # Class names differ per materialization (the namespace is a
        # prefix), so the re-export is compared in the bundle's own
        # identifier space: every generated id is renamed back.
        def self.reexport(expected, classes)
          renames = classes.each_with_object({}) do |(id, klass), map|
            model, _, register = id.rpartition("@")
            map["#{klass.name}@#{register}"] = id if klass.name != model
          end
          roots = expected.roots.map { |id| [classes.fetch(id), id.rpartition("@").last] }
          generated = GraphExporter.export(
            roots.map { |klass, register| [klass, register] },
            projector: method(:project),
          )
          Bundle.new(**rename_tree(generated.to_h, renames, classes).transform_keys(&:to_sym)
                       .slice(:roots, :models, :value_types, :capabilities))
        end

        def self.project(klass, register)
          Exporter.project(klass, register: register == GraphExporter::DEFAULT_REGISTER ? nil : register)
        end

        def self.rename_tree(node, renames, classes, key = nil)
          case node
          when ::Hash
            node.to_h do |k, v|
              [renames.fetch(k, k), rename_tree(v, renames, classes, k)]
            end
          when Array then node.map { |item| rename_tree(item, renames, classes, key) }
          when ::String then rename_string(node, renames, classes, key)
          else node
          end
        end

        def self.rename_string(string, renames, classes, key)
          return renames.fetch(string) if renames.key?(string)

          if key == "model"
            klass = classes.values.find { |c| c.name == string }
            return classes.key(klass).rpartition("@").first if klass
          end
          string
        end

        private_class_method :reconstruct, :reexport, :project, :rename_tree, :rename_string

        def initialize(document, register: nil)
          @document = document
          @register = register
        end

        def verify
          klass = resolve_model!
          reexported = Exporter.export(klass, register: @register)
          return reexported if reexported.canonical_json == @document.canonical_json

          raise RejectedError.new(:round_trip_mismatch, klass,
                                  "the document does not re-derive the model " \
                                  "(#{short(@document.checksum)} vs #{short(reexported.checksum)})")
        end

        private

        def resolve_model!
          name = @document.model_name
          begin
            Object.const_get(name)
          rescue NameError
            raise RejectedError.new(:unknown_type, name, "the recorded model is not loadable")
          end
        end

        def short(checksum)
          checksum.to_s.slice(0, 20)
        end
      end
    end
  end
end
