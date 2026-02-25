# frozen_string_literal: true

require "json"

module Lutaml
  module KeyValue
    module Adapter
      module Json
        autoload :Document, "lutaml/key_value/adapter/json/document"
        autoload :Mapping, "lutaml/key_value/adapter/json/mapping"
        autoload :MappingRule, "lutaml/key_value/adapter/json/mapping_rule"
        autoload :Transform, "lutaml/key_value/adapter/json/transform"
        autoload :StandardAdapter,
                 "lutaml/key_value/adapter/json/standard_adapter"
        autoload :OjAdapter, "lutaml/key_value/adapter/json/oj_adapter"
        autoload :MultiJsonAdapter,
                 "lutaml/key_value/adapter/json/multi_json_adapter"
      end
    end
  end
end
