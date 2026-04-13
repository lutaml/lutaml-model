# frozen_string_literal: true

# JSONL format module
# Provides Lutaml::Jsonl namespace for JSONL serialization

module Lutaml
  module Jsonl
    class Error < StandardError; end

    autoload :Adapter, "#{__dir__}/jsonl/adapter"
  end
end

# Register JSONL format with the format registry
Lutaml::Model::FormatRegistry.register(
  :jsonl,
  mapping_class: Lutaml::Jsonl::Adapter::Mapping,
  adapter_class: Lutaml::Jsonl::Adapter::StandardAdapter,
  transformer: Lutaml::Jsonl::Adapter::Transform,
  key_value: true,
)
