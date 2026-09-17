# frozen_string_literal: true

module Lutaml
  module Yaml
    module Adapter
      autoload :Document, "#{__dir__}/adapter/document"
      autoload :Mapping, "#{__dir__}/adapter/mapping"
      autoload :MappingRule, "#{__dir__}/adapter/mapping_rule"
      autoload :Transform, "#{__dir__}/adapter/transform"
      autoload :StandardAdapter, "#{__dir__}/adapter/standard_adapter"
      # MRI-only native engine adapter (libyeptris FFI)
      Lutaml::Model::RuntimeCompatibility.autoload_native(
        self,
        YeptrisAdapter: "#{__dir__}/adapter/yeptris_adapter",
      )
    end
  end
end
