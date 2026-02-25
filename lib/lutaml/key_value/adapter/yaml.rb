# frozen_string_literal: true

require "yaml"

module Lutaml
  module KeyValue
    module Adapter
      module Yaml
        autoload :Document, "lutaml/key_value/adapter/yaml/document"
        autoload :Mapping, "lutaml/key_value/adapter/yaml/mapping"
        autoload :MappingRule, "lutaml/key_value/adapter/yaml/mapping_rule"
        autoload :Transform, "lutaml/key_value/adapter/yaml/transform"
        autoload :StandardAdapter,
                 "lutaml/key_value/adapter/yaml/standard_adapter"
      end
    end
  end
end
