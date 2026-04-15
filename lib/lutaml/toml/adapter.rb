# frozen_string_literal: true

module Lutaml
  module Toml
    module Adapter
      autoload :Document, "#{__dir__}/adapter/document"
      autoload :Mapping, "#{__dir__}/adapter/mapping"
      autoload :MappingRule, "#{__dir__}/adapter/mapping_rule"
      autoload :Transform, "#{__dir__}/adapter/transform"
      autoload :TomlRbAdapter, "#{__dir__}/adapter/toml_rb_adapter"
      autoload :TomlibAdapter, "#{__dir__}/adapter/tomlib_adapter"
    end
  end
end
