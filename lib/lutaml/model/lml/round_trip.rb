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
      class RoundTrip
        def self.verify(document, register: nil)
          new(document, register: register).verify
        end

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
