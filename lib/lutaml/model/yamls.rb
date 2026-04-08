# frozen_string_literal: true

# YAMLS format entry point
# Provides Lutaml::Model::Yamls namespace that delegates to Lutaml::Yamls

require_relative "../yamls"

# Backward compatibility aliases
module Lutaml
  module Model
    module Yamls
      StandardAdapter = ::Lutaml::Yamls::Adapter::StandardAdapter
      Document = ::Lutaml::Yamls::Adapter::Document
      Mapping = ::Lutaml::Yamls::Adapter::Mapping
      MappingRule = ::Lutaml::Yamls::Adapter::MappingRule
      Transform = ::Lutaml::Yamls::Adapter::Transform
    end
  end
end

# Register YAMLS format with the format registry
Lutaml::Model::FormatRegistry.register(
  :yamls,
  mapping_class: Lutaml::Yamls::Adapter::Mapping,
  adapter_class: Lutaml::Yamls::Adapter::StandardAdapter,
  transformer: Lutaml::Yamls::Adapter::Transform,
  key_value: true,
)
