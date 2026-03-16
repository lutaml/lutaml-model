# frozen_string_literal: true

# Backward compatibility - BaseAdapter has moved to Lutaml::Xml::Adapter::BaseAdapter
require_relative "adapter/base_adapter"

# Alias for backward compatibility
Lutaml::Xml::BaseAdapter = Lutaml::Xml::Adapter::BaseAdapter
