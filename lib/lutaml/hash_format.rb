# frozen_string_literal: true

# Hash format module
# Provides Lutaml::HashFormat namespace for Hash serialization

require_relative "key_value"

module Lutaml
  module HashFormat
    class Error < StandardError; end
  end
end

require_relative "hash_format/adapter/document"
require_relative "hash_format/adapter/mapping"
require_relative "hash_format/adapter/mapping_rule"
require_relative "hash_format/adapter/transform"
require_relative "hash_format/adapter/standard_adapter"

module Lutaml
  module HashFormat
    # Convenience aliases for common classes at the module level
    # Allows Lutaml::HashFormat::Mapping to resolve to Lutaml::HashFormat::Adapter::Mapping
    def self.const_missing(name)
      if Adapter.const_defined?(name, false)
        Adapter.const_get(name, false)
      else
        super
      end
    end
  end
end
