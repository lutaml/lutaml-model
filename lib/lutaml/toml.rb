# frozen_string_literal: true

# TOML format module
# Provides Lutaml::Toml namespace for TOML serialization

module Lutaml
  module Toml
    class Error < StandardError; end

    autoload :Adapter, "#{__dir__}/toml/adapter"
  end
end

# Register TOML format with the format registry
Lutaml::Model::FormatRegistry.register(
  :toml,
  mapping_class: Lutaml::Toml::Adapter::Mapping,
  adapter_class: Lutaml::Toml::Adapter::TomlibAdapter,
  transformer: Lutaml::Toml::Adapter::Transform,
  key_value: true,
)

# Register TOML type serializers
require_relative "toml/type/serializers"
Lutaml::Toml::Type::Serializers.register_all!
