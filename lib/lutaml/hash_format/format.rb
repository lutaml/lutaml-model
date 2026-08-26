# frozen_string_literal: true

# Internal Hash format implementation. Loaded from lib/lutaml/hash_format.rb
# (the public entrypoint) and from lib/lutaml/model.rb (so the model
# entrypoint triggers the registration side effects).
# No require_relative "model" here — keeps the require graph acyclic.

module Lutaml
  module HashFormat
    class Error < StandardError; end

    autoload :Adapter, "#{__dir__}/adapter"
  end
end

Lutaml::Model::FormatRegistry.register(
  :hash,
  mapping_class: Lutaml::HashFormat::Adapter::Mapping,
  adapter_class: Lutaml::HashFormat::Adapter::StandardAdapter,
  transformer: Lutaml::HashFormat::Adapter::Transform,
  key_value: true,
  adapter_options: {
    available: %i[standard standard_hash],
    default: :standard,
  },
)

require_relative "type/serializers"
Lutaml::HashFormat::Type::Serializers.register_all!
