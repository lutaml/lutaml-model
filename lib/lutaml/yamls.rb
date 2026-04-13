# frozen_string_literal: true

# YAMLS format module
# Provides Lutaml::Yamls namespace for YAMLS serialization

module Lutaml
  module Yamls
    class Error < StandardError; end

    autoload :Adapter, "#{__dir__}/yamls/adapter"
  end
end

# Register YAMLS format with the format registry
Lutaml::Model::FormatRegistry.register(
  :yamls,
  mapping_class: Lutaml::Yamls::Adapter::Mapping,
  adapter_class: Lutaml::Yamls::Adapter::StandardAdapter,
  transformer: Lutaml::Yamls::Adapter::Transform,
  key_value: true,
)
