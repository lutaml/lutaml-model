# frozen_string_literal: true

require "moxml"

module Lutaml
  module Xml
    module Adapter
      # The moxml facade lane (#1224).
      #
      # The engine is a deployment decision owned by Moxml: this adapter
      # resolves Moxml::Config at every use — never at load — and
      # delegates to the per-engine adapter class. Selection collapses to
      # this single lane; engine names passed to the deprecated selection
      # surface resolve to the per-engine adapters directly, while
      # process-wide engine deployment goes through Moxml::Config.
      class MoxmlAdapter < BaseAdapter
        RESOLUTION_MUTEX = Mutex.new
        # Engine symbol → adapter class. Keyed by the engine name so
        # repointing Moxml::Config.default_adapter mid-process takes
        # effect on the next parse; the hit path is two reads and a
        # Hash lookup (the parse hot path pays for this facade).
        @engine_adapters = {}

        class << self
          attr_reader :engine_adapters

          # The adapter class for the engine Moxml currently resolves to.
          #
          # @return [Class] a BaseAdapter subclass (NokogiriAdapter,
          #   LeptrisAdapter, OgaAdapter, ...)
          def engine_adapter_class
            engine = Moxml::Config.default_adapter ||
              Moxml::Config.runtime_default_adapter
            engine_adapters[engine] || RESOLUTION_MUTEX.synchronize do
              engine_adapters[engine] ||= resolve_engine_adapter(engine)
            end
          end

          # Transparent delegation: instances and parse results are the
          # engine adapter's, so every downstream consumer sees exactly
          # what the engine lane produces.
          def new(...)
            engine_adapter_class.new(...)
          end

          def parse(xml, options = {})
            engine_adapter_class.parse(xml, options)
          end

          private

          def resolve_engine_adapter(engine)
            Moxml::Adapter.load(engine)
            Lutaml::Xml::AdapterLoader.load_adapter_file(
              :xml, "#{engine}_adapter"
            )
            Lutaml::Xml::AdapterLoader.class_for(:xml, "#{engine}_adapter")
          end
        end
      end
    end
  end
end
