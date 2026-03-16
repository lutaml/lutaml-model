# frozen_string_literal: true

# Backward compatibility - OgaAdapter has moved to Lutaml::Xml::Adapter::OgaAdapter
require_relative "adapter/oga_adapter"

# Alias for backward compatibility
Lutaml::Xml::OgaAdapter = Lutaml::Xml::Adapter::OgaAdapter
