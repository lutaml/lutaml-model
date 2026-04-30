# frozen_string_literal: true

# TOML format module
# Provides Lutaml::Toml namespace for TOML serialization

require "lutaml/model/runtime_compatibility"
require_relative "key_value"
require_relative "toml/adapter"

module Lutaml
  module Toml
    class Error < StandardError; end

    # Convenience aliases for common classes at the module level
    # Allows Lutaml::Toml::Mapping to resolve to Lutaml::Toml::Adapter::Mapping
    def self.const_missing(name)
      if Adapter.const_defined?(name, false)
        Adapter.const_get(name, false)
      else
        super
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
  key_value: true,
)

# Register TOML type serializers
require_relative "toml/type/serializers"
Lutaml::Toml::Type::Serializers.register_all!

if (adapter = Lutaml::Model::Toml.detect_toml_adapter)
  Lutaml::Model::Config.toml_adapter_type = adapter
end
