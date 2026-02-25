# frozen_string_literal: true

require "yaml"

module Lutaml
  module KeyValue
    module Adapter
      module Yamls
        autoload :Document, "lutaml/key_value/adapter/yamls/document"
        autoload :Mapping, "lutaml/key_value/adapter/yamls/mapping"
        autoload :MappingRule, "lutaml/key_value/adapter/yamls/mapping_rule"
        autoload :Transform, "lutaml/key_value/adapter/yamls/transform"
        autoload :StandardAdapter,
                 "lutaml/key_value/adapter/yamls/standard_adapter"
      end
    end
  end
end
