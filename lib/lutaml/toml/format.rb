# frozen_string_literal: true

# Internal TOML format implementation. Loaded from lib/lutaml/toml.rb
# (the public entrypoint) and from lib/lutaml/model.rb (so the model
# entrypoint triggers the registration side effects).
# No require_relative "model" here — keeps the require graph acyclic.

require "lutaml/model/runtime_compatibility"
require_relative "../key_value/format"
require_relative "adapter"

module Lutaml
  module Toml
    class Error < StandardError; end

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

Lutaml::Model::FormatRegistry.register(
  :toml,
  mapping_class: Lutaml::Toml::Adapter::Mapping,
  adapter_class: nil,
  transformer: Lutaml::Toml::Adapter::Transform,
  key_value: true,
  adapter_options: if Lutaml::Model.opal?
                     nil
                   else
                     {
                       available: %i[tomlib toml_rb],
                       default: Lutaml::Model::RuntimeCompatibility.windows? ? :toml_rb : :tomlib,
                     }
                   end,
)

require_relative "type/serializers"
Lutaml::Toml::Type::Serializers.register_all!

# Auto-detection is now handled lazily by AdapterResolver on first use.
# No eager adapter selection at require time.
