# frozen_string_literal: true

# YAML format entry point
# Provides Lutaml::Model::Yaml namespace that delegates to Lutaml::Yaml

require_relative "../yaml"

# Backward compatibility aliases
module Lutaml
  module Model
    module Yaml
      StandardAdapter = ::Lutaml::Yaml::Adapter::StandardAdapter
      Document = ::Lutaml::Yaml::Adapter::Document
      Mapping = ::Lutaml::Yaml::Adapter::Mapping
      MappingRule = ::Lutaml::Yaml::Adapter::MappingRule
      Transform = ::Lutaml::Yaml::Adapter::Transform
    end
  end
end

# Register YAML format with the format registry
Lutaml::Model::FormatRegistry.register(
  :yaml,
  mapping_class: Lutaml::Yaml::Adapter::Mapping,
  adapter_class: Lutaml::Yaml::Adapter::StandardAdapter,
  transformer: Lutaml::Yaml::Adapter::Transform,
  key_value: true,
)

# Register YAML type serializers
require_relative "../yaml/type/serializers"
Lutaml::Yaml::Type::Serializers.register_all!
