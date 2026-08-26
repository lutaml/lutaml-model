# frozen_string_literal: true

# Internal JSON format implementation. Loaded from lib/lutaml/json.rb
# (the public entrypoint) and from lib/lutaml/model.rb (so the model
# entrypoint triggers the registration side effects).
# No require_relative "model" here — keeps the require graph acyclic.

require "lutaml/model/runtime_compatibility"
require_relative "../key_value/format"

module Lutaml
  module Json
    class Error < StandardError; end

    require_relative "adapter/document"
    require_relative "adapter/mapping"
    require_relative "adapter/mapping_rule"
    require_relative "adapter/transform"
    require_relative "adapter/standard_adapter"
    Lutaml::Model::RuntimeCompatibility.require_native(
      "#{__dir__}/adapter/oj_adapter",
      "#{__dir__}/adapter/multi_json_adapter",
    )
    require_relative "schema"

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
      return :standard if defined?(::JSON) && Lutaml::Model.opal?
      return :oj if defined?(::Oj)
      return :multi_json if defined?(::MultiJson)
      return :standard if defined?(::JSON)

      nil
    end
  end
end

Lutaml::Model::FormatRegistry.register(
  :json,
  mapping_class: Lutaml::Json::Adapter::Mapping,
  adapter_class: Lutaml::Json::Adapter::StandardAdapter,
  transformer: Lutaml::Json::Adapter::Transform,
  key_value: true,
  adapter_options: {
    available: %i[standard standard_json multi_json oj],
    default: :standard,
  },
)

require_relative "type/serializers"
Lutaml::Json::Type::Serializers.register_all!
