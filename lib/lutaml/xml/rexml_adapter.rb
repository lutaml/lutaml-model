# frozen_string_literal: true

# Backward compatibility - RexmlAdapter has moved to Lutaml::Xml::Adapter::RexmlAdapter
require_relative "adapter/rexml_adapter"

# Alias for backward compatibility
Lutaml::Xml::RexmlAdapter = Lutaml::Xml::Adapter::RexmlAdapter
