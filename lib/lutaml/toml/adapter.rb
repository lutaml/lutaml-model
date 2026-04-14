# frozen_string_literal: true

require "lutaml/model/runtime_compatibility"

module Lutaml
  module Toml
    module Adapter
      autoload :Document, "#{__dir__}/adapter/document"
      autoload :Mapping, "#{__dir__}/adapter/mapping"
      autoload :MappingRule, "#{__dir__}/adapter/mapping_rule"
      autoload :Transform, "#{__dir__}/adapter/transform"
      Lutaml::Model::RuntimeCompatibility.autoload_native(
        self,
        TomlRbAdapter: "#{__dir__}/adapter/toml_rb_adapter",
        TomlibAdapter: "#{__dir__}/adapter/tomlib_adapter",
      )
    end
  end
end
