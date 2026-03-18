# frozen_string_literal: true

# JSON format entry point
# Provides Lutaml::Json namespace that delegates to KeyValue::Adapter::Json

require_relative "../json"

# Backward compatibility aliases for Lutaml::Model::Json namespace
module Lutaml
  module Model
    module Json
      StandardAdapter = ::Lutaml::Json::Adapter::StandardAdapter
      Document = ::Lutaml::Json::Adapter::Document
      Mapping = ::Lutaml::Json::Mapping
      MappingRule = ::Lutaml::Json::MappingRule
      Transform = ::Lutaml::Json::Transform
      OjAdapter = ::Lutaml::Json::Adapter::OjAdapter
      MultiJsonAdapter = ::Lutaml::Json::Adapter::MultiJsonAdapter
    end
  end
end

# Register JSON format with the format registry
Lutaml::Model::FormatRegistry.register(
  :json,
  mapping_class: Lutaml::Json::Mapping,
  adapter_class: Lutaml::Json::Adapter::StandardAdapter,
  transformer: Lutaml::Json::Transform,
)
