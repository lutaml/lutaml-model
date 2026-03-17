# frozen_string_literal: true

# YAML format module
# Provides Lutaml::Yaml namespace for YAML serialization

require_relative "key_value"

module Lutaml
  module Yaml
    class Error < StandardError; end
  end
end

require_relative "yaml/adapter/document"
require_relative "yaml/adapter/mapping"
require_relative "yaml/adapter/mapping_rule"
require_relative "yaml/adapter/transform"
require_relative "yaml/adapter/standard_adapter"
require_relative "yaml/schema"

module Lutaml
  module Yaml
    # Convenience aliases for common classes at the module level
    # Allows Lutaml::Yaml::Mapping to resolve to Lutaml::Yaml::Adapter::Mapping
    def self.const_missing(name)
      if Adapter.const_defined?(name, false)
        Adapter.const_get(name, false)
      else
        super
      end
    end
  end
end
