# frozen_string_literal: true

module Lutaml
  module Model
    module Yaml
    end
  end
end

require_relative "yaml/standard_adapter"
require_relative "yaml/document"
require_relative "yaml/mapping"
require_relative "yaml/mapping_rule"
require_relative "yaml/transform"

Lutaml::Model::FormatRegistry.register(
  :yaml,
  mapping_class: Lutaml::Model::Yaml::Mapping,
  adapter_class: Lutaml::Model::Yaml::StandardAdapter,
  transformer: Lutaml::Model::Yaml::Transform,
)
