# frozen_string_literal: true

# Hash format module
# Provides Lutaml::HashFormat namespace for Hash serialization

module Lutaml
  module HashFormat
    class Error < StandardError; end

    autoload :Adapter, "#{__dir__}/hash_format/adapter"
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
require_relative "hash_format/type/serializers"
Lutaml::HashFormat::Type::Serializers.register_all!
