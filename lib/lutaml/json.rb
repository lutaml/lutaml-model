# frozen_string_literal: true

# JSON format module
# Provides Lutaml::Json namespace for JSON serialization

module Lutaml
  module Json
    class Error < StandardError; end

    autoload :Adapter, "#{__dir__}/json/adapter"
    autoload :Schema, "#{__dir__}/json/schema"

    # Detect available JSON adapters
    def self.detect_adapter
      return :oj if defined?(::Oj)
      return :multi_json if defined?(::MultiJson)
      return :standard if defined?(::JSON)

      nil
    end
  end
end

# Register JSON format with the format registry
Lutaml::Model::FormatRegistry.register(
  :json,
  mapping_class: Lutaml::Json::Adapter::Mapping,
  adapter_class: Lutaml::Json::Adapter::StandardAdapter,
  transformer: Lutaml::Json::Adapter::Transform,
  key_value: true,
)

# Register JSON type serializers
require_relative "json/type/serializers"
Lutaml::Json::Type::Serializers.register_all!
