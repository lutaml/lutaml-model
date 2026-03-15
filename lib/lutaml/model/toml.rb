# frozen_string_literal: true

# TOML format entry point
# Provides Lutaml::Model::Toml namespace that delegates to Lutaml::Toml

require_relative "../toml"

# Backward compatibility aliases
module Lutaml
  module Model
    module Toml
      TomlibAdapter = ::Lutaml::Toml::Adapter::TomlibAdapter
      TomlRbAdapter = ::Lutaml::Toml::Adapter::TomlRbAdapter
      Document = ::Lutaml::Toml::Adapter::Document
      Mapping = ::Lutaml::Toml::Adapter::Mapping
      MappingRule = ::Lutaml::Toml::Adapter::MappingRule
      Transform = ::Lutaml::Toml::Adapter::Transform

      def self.detect_toml_adapter
        return :tomlib if Lutaml::Model::Utils.safe_load("tomlib", :Tomlib)
        return :toml_rb if Lutaml::Model::Utils.safe_load("toml-rb", :TomlRb)

        nil
      end
    end
  end
end

# Register TOML format with the format registry
Lutaml::Model::FormatRegistry.register(
  :toml,
  mapping_class: Lutaml::Toml::Adapter::Mapping,
  adapter_class: nil,
  transformer: Lutaml::Toml::Adapter::Transform,
)

if (adapter = Lutaml::Model::Toml.detect_toml_adapter)
  Lutaml::Model::Config.toml_adapter_type = adapter
end
