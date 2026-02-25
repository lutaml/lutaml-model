# frozen_string_literal: true

module Lutaml
  module KeyValue
    module Adapter
      module Toml
        autoload :Document, "lutaml/key_value/adapter/toml/document"
        autoload :Mapping, "lutaml/key_value/adapter/toml/mapping"
        autoload :MappingRule, "lutaml/key_value/adapter/toml/mapping_rule"
        autoload :Transform, "lutaml/key_value/adapter/toml/transform"
        autoload :TomlibAdapter, "lutaml/key_value/adapter/toml/tomlib_adapter"
        autoload :TomlRbAdapter, "lutaml/key_value/adapter/toml/toml_rb_adapter"
      end
    end
  end
end
