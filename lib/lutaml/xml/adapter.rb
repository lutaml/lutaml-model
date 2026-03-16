# frozen_string_literal: true

module Lutaml
  module Xml
    # Adapter namespace for XML adapter internal classes
    module Adapter
      autoload :AdapterHelpers, "#{__dir__}/adapter/adapter_helpers"
      autoload :BaseAdapter, "#{__dir__}/adapter/base_adapter"
      autoload :NamespaceData, "#{__dir__}/adapter/namespace_data"
      autoload :NokogiriAdapter, "#{__dir__}/adapter/nokogiri_adapter"
      autoload :OgaAdapter, "#{__dir__}/adapter/oga_adapter"
      autoload :OxAdapter, "#{__dir__}/adapter/ox_adapter"
      autoload :RexmlAdapter, "#{__dir__}/adapter/rexml_adapter"
    end
  end
end
