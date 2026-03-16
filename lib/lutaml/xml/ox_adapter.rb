# frozen_string_literal: true

# Backward compatibility - OxAdapter has moved to Lutaml::Xml::Adapter::OxAdapter
require_relative "adapter/ox_adapter"

# Alias for backward compatibility
Lutaml::Xml::OxAdapter = Lutaml::Xml::Adapter::OxAdapter
