# frozen_string_literal: true

# JSONL format module
# Provides Lutaml::Jsonl namespace for JSONL serialization

require_relative "key_value"

module Lutaml
  module Jsonl
    class Error < StandardError; end
  end
end

require_relative "jsonl/adapter/document"
require_relative "jsonl/adapter/mapping"
require_relative "jsonl/adapter/mapping_rule"
require_relative "jsonl/adapter/transform"
require_relative "jsonl/adapter/standard_adapter"

module Lutaml
  module Jsonl
    # Convenience aliases for common classes at the module level
    # Allows Lutaml::Jsonl::Mapping to resolve to Lutaml::Jsonl::Adapter::Mapping
    def self.const_missing(name)
      if Adapter.const_defined?(name, false)
        Adapter.const_get(name, false)
      else
        super
      end
    end
  end
end
