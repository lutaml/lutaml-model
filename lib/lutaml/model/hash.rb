# frozen_string_literal: true

# Hash format entry point - uses Lutaml::KeyValue::Adapter::Hash namespace
require_relative "../key_value/adapter/hash/standard_adapter"
require_relative "../key_value/adapter/hash/document"
require_relative "../key_value/adapter/hash/mapping"
require_relative "../key_value/adapter/hash/mapping_rule"
require_relative "../key_value/adapter/hash/transform"

# Backward compatibility alias
module Lutaml
  module Model
    module Hash
      StandardAdapter = Lutaml::KeyValue::Adapter::Hash::StandardAdapter
      Document = Lutaml::KeyValue::Adapter::Hash::Document
      Mapping = Lutaml::KeyValue::Adapter::Hash::Mapping
      MappingRule = Lutaml::KeyValue::Adapter::Hash::MappingRule
      Transform = Lutaml::KeyValue::Adapter::Hash::Transform
    end
  end
end

Lutaml::Model::FormatRegistry.register(
  :hash,
  mapping_class: Lutaml::KeyValue::Adapter::Hash::Mapping,
  adapter_class: Lutaml::KeyValue::Adapter::Hash::StandardAdapter,
  transformer: Lutaml::KeyValue::Adapter::Hash::Transform,
)
