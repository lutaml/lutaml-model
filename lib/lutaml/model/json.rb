# frozen_string_literal: true

# JSON format entry point - uses Lutaml::KeyValue::Adapter::Json namespace
require_relative "../key_value/adapter/json/standard_adapter"
require_relative "../key_value/adapter/json/document"
require_relative "../key_value/adapter/json/mapping"
require_relative "../key_value/adapter/json/mapping_rule"
require_relative "../key_value/adapter/json/transform"

# Backward compatibility alias
module Lutaml
  module Model
    module Json
      StandardAdapter = Lutaml::KeyValue::Adapter::Json::StandardAdapter
      Document = Lutaml::KeyValue::Adapter::Json::Document
      Mapping = Lutaml::KeyValue::Adapter::Json::Mapping
      MappingRule = Lutaml::KeyValue::Adapter::Json::MappingRule
      Transform = Lutaml::KeyValue::Adapter::Json::Transform
    end
  end
end

Lutaml::Model::FormatRegistry.register(
  :json,
  mapping_class: Lutaml::KeyValue::Adapter::Json::Mapping,
  adapter_class: Lutaml::KeyValue::Adapter::Json::StandardAdapter,
  transformer: Lutaml::KeyValue::Adapter::Json::Transform,
)
