# frozen_string_literal: true

require_relative "standard_adapter"

module Lutaml
  module Yamls
    module Adapter
      # YAMLS (multi-document streams) over the yeptris engine
      # (libyeptris C11) once the engine offers tolerant per-document
      # streaming. The adapter owns no YAML parsing of its own: the
      # engine reads the stream, frames documents, and reports
      # per-document errors; lutaml-model never splits or re-parses
      # YAML text itself.
      #
      # Until the engine ships the iterator (requested upstream as the
      # yeptris#881 follow-up), the adapter reports unavailable and the
      # lane keeps the standard adapter, whose tolerance lives engine-
      # side in Psych — so neither lane ever needs host-side parsing.
      class YeptrisAdapter < StandardAdapter
        FORMAT_SYMBOL = :yamls

        # yeptris is required lazily: the ruby-platform variant installs
        # everywhere but only loads where libyeptris exists — a broken
        # install must degrade to detection fallback, never crash loads.
        def self.parse(yamls, _options = {})
          require_engine
          require "yeptris/yaml"

          results = []
          # rubocop:disable-next Naming/VariableNumber -- upstream schema literal
          ::Yeptris::YAML.each_document(yamls, schema: :compat_11) do |doc, error|
            next if error || doc.nil?

            results << doc
          end
          results
        end

        # Mirrors the standard adapter's stream walking: each_document
        # is the engine's stream entry, so parse_with_stream stays a
        # single surface for callers that reach for it directly.
        def self.parse_with_stream(yamls)
          parse(yamls)
        end

        # The engine require sits outside available?'s rescue so a
        # broken install still surfaces its LoadError (the detection
        # fallback's contract) instead of a NameError from the clause.
        def self.require_engine
          require "yeptris"
        end
        private_class_method :require_engine

        # True where the yeptris engine loads (libyeptris present for
        # this platform) AND answers the tolerant per-document iterator
        # this lane requires. load_stream alone cannot skip a failed
        # document without the host re-parsing YAML text itself, which
        # lutaml-model must never do — so without the iterator the
        # adapter reports unavailable and the standard lane serves
        # streams.
        def self.available?
          require_engine
          require "yeptris/yaml"
          native_ready? && ::Yeptris::YAML.respond_to?(:each_document)
        rescue LoadError
          false
        end

        def self.native_ready?
          return @native_ready unless @native_ready.nil?

          @native_ready = begin
            # rubocop:disable-next Naming/VariableNumber -- upstream schema literal
            ::Yeptris::YAML.load("native_probe: 1", schema: :compat_11)
            true
          rescue StandardError
            false
          end
        end
        private_class_method :native_ready?

        def to_yamls(*_args)
          require "yeptris/psych"

          (@yamls || []).map do |yaml|
            # Generation matches the standard (Psych) adapter's
            # byte-for-byte contract through the Psych-compatible face
            # of the same engine (headerless neutral dump would differ).
            ::Yeptris::Psych.dump(yaml).strip
          end.join("\n")
        end
      end
    end
  end
end
