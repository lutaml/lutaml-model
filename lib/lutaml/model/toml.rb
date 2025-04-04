# frozen_string_literal: true

module Lutaml
  module Model
    module Yaml
    end
  end
end

require_relative "toml/document"
require_relative "toml/mapping"
require_relative "toml/mapping_rule"
require_relative "toml/transform"

Lutaml::Model::FormatRegistry.register(
  :toml,
  mapping_class: Lutaml::Model::Toml::Mapping,
  adapter_class: nil,
  transformer: Lutaml::Model::Toml::Transform,
)
