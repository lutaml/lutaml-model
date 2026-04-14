# frozen_string_literal: true

require "lutaml/model/runtime_compatibility"

module Lutaml
  module KeyValue
    module Adapter
      module Toml
        autoload :Document, "#{__dir__}/toml/document"
        autoload :Mapping, "#{__dir__}/toml/mapping"
        autoload :MappingRule, "#{__dir__}/toml/mapping_rule"
        autoload :Transform, "#{__dir__}/toml/transform"
        Lutaml::Model::RuntimeCompatibility.autoload_native(
          self,
          TomlibAdapter: "#{__dir__}/toml/tomlib_adapter",
          TomlRbAdapter: "#{__dir__}/toml/toml_rb_adapter",
        )
      end
    end
  end
end
