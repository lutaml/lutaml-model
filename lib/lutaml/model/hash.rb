# frozen_string_literal: true

# Hash format entry point
# Provides Lutaml::Model::Hash namespace that delegates to Lutaml::HashFormat

require_relative "../hash_format"

# Backward compatibility aliases
module Lutaml
  module Model
    module Hash
      StandardAdapter = ::Lutaml::HashFormat::Adapter::StandardAdapter
      Document = ::Lutaml::HashFormat::Adapter::Document
      Mapping = ::Lutaml::HashFormat::Adapter::Mapping
      MappingRule = ::Lutaml::HashFormat::Adapter::MappingRule
      Transform = ::Lutaml::HashFormat::Adapter::Transform
    end
  end
end

# Register Hash format with the format registry
Lutaml::Model::FormatRegistry.register(
  :hash,
  mapping_class: Lutaml::HashFormat::Adapter::Mapping,
  adapter_class: Lutaml::HashFormat::Adapter::StandardAdapter,
  transformer: Lutaml::HashFormat::Adapter::Transform,
  key_value: true,
)

# Register Hash type serializers
require_relative "../hash_format/type/serializers"
Lutaml::HashFormat::Type::Serializers.register_all!
