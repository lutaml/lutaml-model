# frozen_string_literal: true

# YAML format entry point - uses Lutaml::KeyValue::Adapter::Yaml namespace
# Constants are accessed via autoload from key_value/adapter/yaml.rb

# Backward compatibility alias
module Lutaml
  module Model
    module Yaml
      StandardAdapter = Lutaml::KeyValue::Adapter::Yaml::StandardAdapter
      Document = Lutaml::KeyValue::Adapter::Yaml::Document
      Mapping = Lutaml::KeyValue::Adapter::Yaml::Mapping
      MappingRule = Lutaml::KeyValue::Adapter::Yaml::MappingRule
      Transform = Lutaml::KeyValue::Adapter::Yaml::Transform
    end
  end
end

Lutaml::Model::FormatRegistry.register(
  :yaml,
  mapping_class: Lutaml::KeyValue::Adapter::Yaml::Mapping,
  adapter_class: Lutaml::KeyValue::Adapter::Yaml::StandardAdapter,
  transformer: Lutaml::KeyValue::Adapter::Yaml::Transform,
)
