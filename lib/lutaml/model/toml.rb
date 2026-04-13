# frozen_string_literal: true

# Backward compatibility - provides Lutaml::Model::Toml namespace with helper methods

module Lutaml
  module Model
    module Toml
      TomlibAdapter = ::Lutaml::Toml::Adapter::TomlibAdapter
      TomlRbAdapter = ::Lutaml::Toml::Adapter::TomlRbAdapter
      Document = ::Lutaml::Toml::Adapter::Document
      Mapping = ::Lutaml::Toml::Adapter::Mapping
      MappingRule = ::Lutaml::Toml::Adapter::MappingRule
      Transform = ::Lutaml::Toml::Adapter::Transform

      def self.detect_toml_adapter
        # Skip tomlib on Windows entirely due to segfault issues
        if Gem.win_platform?
          return :toml_rb if Lutaml::Model::Utils.safe_load("toml-rb", :TomlRb)

          return nil
        end

        # On non-Windows, prefer tomlib
        return :tomlib if Lutaml::Model::Utils.safe_load("tomlib", :Tomlib)
        return :toml_rb if Lutaml::Model::Utils.safe_load("toml-rb", :TomlRb)

        nil
      end
    end
  end
end