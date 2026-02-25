# frozen_string_literal: true

# JSONL format entry point - uses Lutaml::KeyValue::Adapter::Jsonl namespace
require_relative "../key_value/adapter/jsonl/standard_adapter"
require_relative "../key_value/adapter/jsonl/document"
require_relative "../key_value/adapter/jsonl/mapping"
require_relative "../key_value/adapter/jsonl/mapping_rule"
require_relative "../key_value/adapter/jsonl/transform"

# Backward compatibility alias
module Lutaml
  module Model
    module Jsonl
      StandardAdapter = Lutaml::KeyValue::Adapter::Jsonl::StandardAdapter
      Document = Lutaml::KeyValue::Adapter::Jsonl::Document
      Mapping = Lutaml::KeyValue::Adapter::Jsonl::Mapping
      MappingRule = Lutaml::KeyValue::Adapter::Jsonl::MappingRule
      Transform = Lutaml::KeyValue::Adapter::Jsonl::Transform
    end
  end
end

Lutaml::Model::FormatRegistry.register(
  :jsonl,
  mapping_class: Lutaml::KeyValue::Adapter::Jsonl::Mapping,
  adapter_class: Lutaml::KeyValue::Adapter::Jsonl::StandardAdapter,
  transformer: Lutaml::KeyValue::Adapter::Jsonl::Transform,
)
