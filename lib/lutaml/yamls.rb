# frozen_string_literal: true

# YAMLS format module
# Provides Lutaml::Yamls namespace for YAMLS serialization

require_relative "key_value"

module Lutaml
  module Yamls
    class Error < StandardError; end
  end
end

require_relative "yamls/adapter/document"
require_relative "yamls/adapter/mapping"
require_relative "yamls/adapter/mapping_rule"
require_relative "yamls/adapter/transform"
require_relative "yamls/adapter/standard_adapter"

module Lutaml
  module Yamls
    # Convenience aliases for common classes at the module level
    # Allows Lutaml::Yamls::Mapping to resolve to Lutaml::Yamls::Adapter::Mapping
    def self.const_missing(name)
      if Adapter.const_defined?(name, false)
        Adapter.const_get(name, false)
      else
        super
      end
    end
  end
end
