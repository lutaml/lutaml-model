# frozen_string_literal: true

# JSON format module
# Provides Lutaml::Json namespace for JSON serialization

require "lutaml/model/runtime_compatibility"
require_relative "model"
require_relative "key_value"

module Lutaml
  module Json
    class Error < StandardError; end

    require_relative "json/adapter/document"
    require_relative "json/adapter/mapping"
    require_relative "json/adapter/mapping_rule"
    require_relative "json/adapter/transform"
    require_relative "json/adapter/standard_adapter"
    Lutaml::Model::RuntimeCompatibility.require_native(
      "#{__dir__}/json/adapter/oj_adapter",
      "#{__dir__}/json/adapter/multi_json_adapter",
    )
    require_relative "json/schema"

    # Convenience aliases for common classes at the module level
    # Allows Lutaml::Json::Mapping to resolve to Lutaml::Json::Adapter::Mapping
    def self.const_missing(name)
      if Adapter.const_defined?(name, false)
        Adapter.const_get(name, false)
      else
        super
      end
    end

    # Detect available JSON adapters
    def self.detect_adapter
      return :standard if defined?(::JSON) && Lutaml::Model::RuntimeCompatibility.opal?
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
