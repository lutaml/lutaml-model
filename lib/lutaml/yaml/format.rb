# frozen_string_literal: true

# Internal YAML format implementation. Loaded from lib/lutaml/yaml.rb
# (the public entrypoint) and from lib/lutaml/model.rb (so the model
# entrypoint triggers the registration side effects).
# No require_relative "model" here — keeps the require graph acyclic.

module Lutaml
  module Yaml
    class Error < StandardError; end

    autoload :Adapter, "#{__dir__}/adapter"
    autoload :Schema, "#{__dir__}/schema"
  end
end

Lutaml::Model::FormatRegistry.register(
  :yaml,
  mapping_class: Lutaml::Yaml::Adapter::Mapping,
  adapter_class: Lutaml::Yaml::Adapter::StandardAdapter,
  transformer: Lutaml::Yaml::Adapter::Transform,
  key_value: true,
  adapter_options: {
    available: %i[standard standard_yaml],
    default: :standard,
  },
)

require_relative "type/serializers"
Lutaml::Yaml::Type::Serializers.register_all!
