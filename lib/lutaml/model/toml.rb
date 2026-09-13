# frozen_string_literal: true

# Backward compatibility - provides Lutaml::Model::Toml namespace with helper methods

module Lutaml
  module Model
    module Toml
      Lutaml::Model::RuntimeCompatibility.define_native_aliases(
        self,
        TeptrisAdapter: "::Lutaml::Toml::Adapter::TeptrisAdapter",
        TomlibAdapter: "::Lutaml::Toml::Adapter::TomlibAdapter",
        TomlRbAdapter: "::Lutaml::Toml::Adapter::TomlRbAdapter",
      )
      Document = ::Lutaml::Toml::Adapter::Document
      Mapping = ::Lutaml::Toml::Adapter::Mapping
      MappingRule = ::Lutaml::Toml::Adapter::MappingRule
      Transform = ::Lutaml::Toml::Adapter::Transform

      def self.detect_toml_adapter
        return nil if Lutaml::Model.opal?

        # teptris 0.2.12+ parses ~3x and dumps ~8x faster than tomlib
        # and ships prebuilts for every platform (mingw-ucrt restored
        # in 0.2.4+) — native TOML on Windows retires the tomlib
        # segfault workaround (previously pure-Ruby toml-rb only).
        return :teptris if Lutaml::Model::Utils.safe_load("teptris", :Teptris)

        # tomlib segfaults on Windows when parsing invalid TOML
        if !Lutaml::Model::RuntimeCompatibility.windows? &&
            Lutaml::Model::Utils.safe_load("tomlib", :Tomlib)
          return :tomlib
        end

        return :toml_rb if Lutaml::Model::Utils.safe_load("toml-rb", :TomlRb)

        nil
      end
    end
  end
end
