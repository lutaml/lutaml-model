# frozen_string_literal: true

# Internal JSONL format implementation. Loaded from lib/lutaml/jsonl.rb
# (the public entrypoint) and from lib/lutaml/model.rb (so the model
# entrypoint triggers the registration side effects).
# No require_relative "model" here — keeps the require graph acyclic.

module Lutaml
  module Jsonl
    class Error < StandardError; end

    autoload :Adapter, "#{__dir__}/adapter"
  end
end

Lutaml::Model::FormatRegistry.register(
  :jsonl,
  mapping_class: Lutaml::Jsonl::Adapter::Mapping,
  adapter_class: Lutaml::Jsonl::Adapter::StandardAdapter,
  transformer: Lutaml::Jsonl::Adapter::Transform,
  key_value: true,
)
