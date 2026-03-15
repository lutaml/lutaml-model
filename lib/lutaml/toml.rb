# frozen_string_literal: true

# TOML format module
# Provides Lutaml::Toml namespace for TOML serialization

require_relative "key_value"

module Lutaml
  module Toml
    class Error < StandardError; end
  end
end

require_relative "toml/adapter/document"
require_relative "toml/adapter/mapping"
require_relative "toml/adapter/mapping_rule"
require_relative "toml/adapter/transform"
require_relative "toml/adapter/toml_rb_adapter"
require_relative "toml/adapter/tomlib_adapter"

module Lutaml
  module Toml
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
