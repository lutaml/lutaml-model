# frozen_string_literal: true

require "moxml"

module Lutaml
  module Xml
    module Adapter
      # THE XML adapter: one moxml-backed lane, engine as data.
      #
      # Every XML parse/serialize rides this class; the ENGINE is a
      # deployment decision resolved as follows:
      #
      # - The class itself is the DEFERRED (facade) lane (#1224): the
      #   engine resolves at call time from moxml's runtime answer.
      # - `for_engine(engine)` returns a memoized pinned subclass for
      #   an explicit engine selection (AdapterResolver type pins such
      #   as :nokogiri, and per-operation overrides such as
      #   `from_xml ..., adapter: :ox`).
      #
      # The per-engine adapter classes this replaces were constant
      # shells differing only in the engine triple (moxml adapter,
      # builder, element class); the per-engine builder subclasses
      # differed by one symbol. The engine contract now lives in
      # ENGINE_CONFIGS and the single AdapterElement serves every
      # engine.
      class MoxmlAdapter < BaseAdapter
        class << self
          # Engine registry: the lazy requires keep this file free of
          # native-only dependencies at load time (the Opal boot
          # requires this file unconditionally). `parse_error` is the
          # engine error class the parse boundary rescues into a
          # format error (nil = ride moxml's own error surface); the
          # rexml entry carries the historical empty-document error
          # contract (:parse_exception / REXML::ParseException).
          ENGINE_CONFIGS = {
            nokogiri: {
              requires: ["moxml/adapter/nokogiri"],
              moxml_adapter: "Moxml::Adapter::Nokogiri",
              parse_error: nil,
            },
            leptris: {
              requires: ["moxml/adapter/leptris"],
              moxml_adapter: "Moxml::Adapter::Leptris",
              parse_error: "Moxml::ParseError",
            },
            oga: {
              requires: ["oga", "moxml/adapter/oga"],
              moxml_adapter: "Moxml::Adapter::Oga",
              parse_error: nil,
            },
            ox: {
              requires: ["moxml/adapter/ox"],
              moxml_adapter: "Moxml::Adapter::Ox",
              parse_error: "Moxml::ParseError",
            },
            rexml: {
              requires: ["rexml/document", "moxml/adapter/rexml"],
              moxml_adapter: "Moxml::Adapter::Rexml",
              parse_error: nil,
              empty_document_error_message: "Malformed XML: Unable to parse " \
                                            "the provided XML document. The document structure is invalid " \
                                            "or incomplete.",
              empty_document_error_type: :parse_exception,
            },
          }.freeze

          # The pinned adapter class for an engine. Memoized per
          # process: a bundle that pins :leptris keeps the leptris
          # lane, a :nokogiri pin keeps nokogiri, without re-resolving
          # per parse.
          def for_engine(engine)
            engine = engine.to_sym
            return self if engine == :moxml

            @for_engine_mutex ||= Mutex.new
            @for_engine_mutex.synchronize do
              @for_engine ||= {}
              @for_engine[engine] ||= begin
                unless ENGINE_CONFIGS.key?(engine)
                  raise ArgumentError,
                        "unknown XML engine: `:#{engine}` (known engines: " \
                        "#{ENGINE_CONFIGS.keys.map { |e| ":#{e}" }.join(', ')})"
                end

                engine_name = engine
                Class.new(self) do
                  @__engine = engine_name
                end
              end
            end
          end

          # The engine serving this lane: the pin for a for_engine
          # subclass; the deferred lane resolves at call time from
          # moxml's runtime answer.
          def engine_name
            if instance_variable_defined?(:@__engine) && @__engine
              @__engine
            else
              Lutaml::Xml.moxml_engine
            end
          end

          # The lane identity keyed by consumers and specs
          # (expected_<type>_* helpers) — the engine name, not the
          # anonymous-subclass inspection the base class-name
          # derivation would answer.
          def type
            engine_name.to_s
          end

          def parsed_element_class
            Lutaml::Xml::AdapterElement
          end

          def moxml_adapter_class
            config = ENGINE_CONFIGS.fetch(engine_name)
            config[:requires].each { |path| require path }
            Object.const_get(config[:moxml_adapter])
          end

          def parse_error_class_or_nil
            name = ENGINE_CONFIGS.fetch(engine_name)[:parse_error]
            name && Object.const_get(name)
          end

          def empty_document_error_message
            ENGINE_CONFIGS.fetch(engine_name)[:empty_document_error_message] ||
              super
          end

          def empty_document_error_type
            ENGINE_CONFIGS.fetch(engine_name)[:empty_document_error_type] ||
              super
          end
        end
      end
    end
  end
end
