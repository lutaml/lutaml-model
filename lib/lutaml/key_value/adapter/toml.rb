# frozen_string_literal: true

module Lutaml
  module KeyValue
    module Adapter
      module Toml
        autoload :Document, "#{__dir__}/toml/document"
        autoload :Mapping, "#{__dir__}/toml/mapping"
        autoload :MappingRule, "#{__dir__}/toml/mapping_rule"
        autoload :Transform, "#{__dir__}/toml/transform"
        autoload :TomlibAdapter, "#{__dir__}/toml/tomlib_adapter"
        autoload :TomlRbAdapter, "#{__dir__}/toml/toml_rb_adapter"
      end
    end
  end
end
