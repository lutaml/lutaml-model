# frozen_string_literal: true

# YAML format module
# Provides Lutaml::Yaml namespace for YAML serialization

module Lutaml
  module Yaml
    class Error < StandardError; end

    autoload :Adapter, "#{__dir__}/yaml/adapter"
    autoload :Schema, "#{__dir__}/yaml/schema"
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
require_relative "yaml/type/serializers"
Lutaml::Yaml::Type::Serializers.register_all!
