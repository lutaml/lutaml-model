# frozen_string_literal: true

require "moxml"

module Lutaml
  module Xml
    module Adapter
      # The deferred (facade) lane (#1224): the `:moxml` adapter type.
      #
      # Every other XML adapter freezes its engine into constants
      # (MOXML_ADAPTER, BUILDER_CLASS, PARSED_ELEMENT_CLASS); this one
      # defers the ENGINE decision to Moxml at call time — the same
      # authority detection has always used ("moxml is the authority on
      # XML adapter availability"). The engine stays a deployment
      # decision owned by Moxml::Config: a bundle that pins moxml's
      # default to leptris gets the leptris lane, a nokogiri pin gets
      # nokogiri, without re-selecting per parse. Per-engine adapter
      # classes are resolved through the adapter loader and cached, so
      # the per-call cost is one `Moxml::Config.default_adapter` query
      # plus a Hash lookup.
      class MoxmlAdapter < BaseAdapter
        class << self
          # The engine-backed adapter for moxml's answer, cached per
          # engine name. `Moxml::Config.default_adapter` is the
          # authority: a bundle that pinned moxml's adapter gets that
          # engine; otherwise it falls through to moxml's runtime
          # availability answer — the same query detection has always
          # used. Resolution rides the adapter loader (file naming and
          # class resolution mirror AdapterResolver.load_adapter), so a
          # missing engine gem surfaces as the loader's
          # UnknownAdapterTypeError with the real LoadError chained as
          # its cause.
          def resolved_adapter
            engine = Moxml::Config.default_adapter
            @resolved_adapters ||= {}
            @resolved_adapters[engine] ||= resolve_engine_adapter(engine)
          end

          def moxml_adapter_class
            resolved_adapter.moxml_adapter_class
          end

          def builder_class
            resolved_adapter.builder_class
          end

          def parsed_element_class
            resolved_adapter.parsed_element_class
          end

          def parse_error_class_or_nil
            resolved_adapter.parse_error_class_or_nil
          end

          def empty_document_error_message
            resolved_adapter.empty_document_error_message
          end

          def empty_document_error_type
            resolved_adapter.empty_document_error_type
          end

          private

          # The loader's normalization shape: :leptris ->
          # "leptris_adapter" -> Lutaml::Xml::Adapter::LeptrisAdapter.
          def resolve_engine_adapter(engine)
            type_name = "#{engine}_adapter"
            AdapterLoader.load_adapter_file(:xml, type_name)
            AdapterLoader.class_for(:xml, type_name)
          end
        end
      end
    end
  end
end
