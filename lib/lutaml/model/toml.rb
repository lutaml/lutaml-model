# frozen_string_literal: true

# TOML format entry point - uses Lutaml::KeyValue::Adapter::Toml namespace

# Backward compatibility alias
module Lutaml
  module Model
    module Toml
      TomlibAdapter = Lutaml::KeyValue::Adapter::Toml::TomlibAdapter
      TomlRbAdapter = Lutaml::KeyValue::Adapter::Toml::TomlRbAdapter
      Document = Lutaml::KeyValue::Adapter::Toml::Document
      Mapping = Lutaml::KeyValue::Adapter::Toml::Mapping
      MappingRule = Lutaml::KeyValue::Adapter::Toml::MappingRule
      Transform = Lutaml::KeyValue::Adapter::Toml::Transform

      def self.detect_toml_adapter
        return :tomlib if Lutaml::Model::Utils.safe_load("tomlib", :Tomlib)
        return :toml_rb if Lutaml::Model::Utils.safe_load("toml-rb", :TomlRb)

        nil
      end
    end
  end
end

Lutaml::Model::FormatRegistry.register(
  :toml,
  mapping_class: Lutaml::KeyValue::Adapter::Toml::Mapping,
  adapter_class: nil,
  transformer: Lutaml::KeyValue::Adapter::Toml::Transform,
)

if (adapter = Lutaml::Model::Toml.detect_toml_adapter)
  Lutaml::Model::Config.toml_adapter_type = adapter
end
