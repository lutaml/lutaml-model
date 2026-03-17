# frozen_string_literal: true

# JSON format module
# Provides Lutaml::Json namespace for JSON serialization

module Lutaml
  module Json
    class Error < StandardError; end
  end
end

require_relative "json/adapter/document"
require_relative "json/adapter/mapping"
require_relative "json/adapter/mapping_rule"
require_relative "json/adapter/transform"
require_relative "json/adapter/standard_adapter"
require_relative "json/adapter/oj_adapter"
require_relative "json/adapter/multi_json_adapter"
require_relative "json/schema"

module Lutaml
  module Json
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
      return :oj if defined?(::Oj)
      return :multi_json if defined?(::MultiJson)
      return :standard if defined?(::JSON)

      nil
    end
  end
end
