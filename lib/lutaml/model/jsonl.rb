# frozen_string_literal: true

# JSONL format entry point
# Provides Lutaml::Model::Jsonl namespace that delegates to Lutaml::Jsonl

require_relative "../jsonl"

# Backward compatibility aliases
module Lutaml
  module Model
    module Jsonl
      StandardAdapter = ::Lutaml::Jsonl::Adapter::StandardAdapter
      Document = ::Lutaml::Jsonl::Adapter::Document
      Mapping = ::Lutaml::Jsonl::Adapter::Mapping
      MappingRule = ::Lutaml::Jsonl::Adapter::MappingRule
      Transform = ::Lutaml::Jsonl::Adapter::Transform
    end
  end
end

# Register JSONL format with the format registry
Lutaml::Model::FormatRegistry.register(
  :jsonl,
  mapping_class: Lutaml::Jsonl::Adapter::Mapping,
  adapter_class: Lutaml::Jsonl::Adapter::StandardAdapter,
  transformer: Lutaml::Jsonl::Adapter::Transform,
  key_value: true,
)
