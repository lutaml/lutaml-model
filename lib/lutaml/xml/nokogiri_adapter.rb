# frozen_string_literal: true

# Backward compatibility - NokogiriAdapter has moved to Lutaml::Xml::Adapter::NokogiriAdapter
require_relative "adapter/nokogiri_adapter"

# Alias for backward compatibility
Lutaml::Xml::NokogiriAdapter = Lutaml::Xml::Adapter::NokogiriAdapter
