# frozen_string_literal: true

require "moxml"

module Lutaml
  module Xml
    module Adapter
      # The deferred (facade) lane (#1224): the `:moxml` adapter type.
      # The ENGINE resolves at call time from moxml's runtime answer —
      # the engine stays a deployment decision owned by moxml, the way
      # detection has always treated it ("moxml is the authority on
      # XML adapter availability"). Resolution caches per engine name:
      # a bundle that pins moxml's default to leptris gets the
      # leptris lane, a nokogiri pin gets nokogiri, without
      # re-resolving per parse.
      class MoxmlAdapter < BaseAdapter
        class << self
          def resolved_adapter
            engine = Moxml::Config.runtime_default_adapter
            @resolved ||= {}
            @resolved[engine] ||= begin
              # the loader's normalization shape: :leptris ->
              # "leptris_adapter" -> Lutaml::Xml::Adapter::LeptrisAdapter
              type_name = "#{engine}_adapter"
              Lutaml::Xml::AdapterLoader.load_adapter_file(:xml, type_name)
              Lutaml::Xml::AdapterLoader.class_for(:xml, type_name)
            end
          end

          def parsed_element_class
            resolved_adapter.parsed_element_class
          end

          def moxml_adapter_class
            resolved_adapter.moxml_adapter_class
          end

          def parse_error_class_or_nil
            resolved_adapter.parse_error_class_or_nil
          end
        end
      end
    end
  end
end
