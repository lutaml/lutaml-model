# frozen_string_literal: true

module Lutaml
  module Xml
    # Adapter namespace for XML adapter internal classes
    module Adapter
      autoload :AdapterHelpers, "#{__dir__}/adapter/adapter_helpers"
      autoload :BaseAdapter, "#{__dir__}/adapter/base_adapter"
      autoload :NamespaceData, "#{__dir__}/adapter/namespace_data"
      autoload :XmlParser, "#{__dir__}/adapter/xml_parser"
      autoload :XmlSerializer, "#{__dir__}/adapter/xml_serializer"
      autoload :PlanBasedBuilder, "#{__dir__}/adapter/plan_based_builder"
      autoload :NamespaceUriCollector,
               "#{__dir__}/adapter/namespace_uri_collector"
      # Plain autoload (in addition to the native table): the Opal boot
      # generator harvests `autoload :Name, "path"` declarations only,
      # so the facade must appear here to ride the sequential boot.
      autoload :MoxmlAdapter, "#{__dir__}/adapter/moxml_adapter"
      Lutaml::Model::RuntimeCompatibility.autoload_native(
        self,
        MoxmlAdapter: "#{__dir__}/adapter/moxml_adapter",
      )
    end
  end
end
