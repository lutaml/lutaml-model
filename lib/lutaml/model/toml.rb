# frozen_string_literal: true

module Lutaml
  module Model
    module Toml
      def self.detect_toml_adapter
        return :tomlib if Utils.safe_load("tomlib", :Tomlib)
        return :toml_rb if Utils.safe_load("toml-rb", :TomlRb)

        nil
      end
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

if (adapter = Lutaml::Model::Toml.detect_toml_adapter)
  Lutaml::Model::Config.toml_adapter_type = adapter
end
