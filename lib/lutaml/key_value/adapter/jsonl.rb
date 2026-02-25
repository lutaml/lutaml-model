# frozen_string_literal: true

require "json"

module Lutaml
  module KeyValue
    module Adapter
      module Jsonl
        autoload :Document, "lutaml/key_value/adapter/jsonl/document"
        autoload :Mapping, "lutaml/key_value/adapter/jsonl/mapping"
        autoload :MappingRule, "lutaml/key_value/adapter/jsonl/mapping_rule"
        autoload :Transform, "lutaml/key_value/adapter/jsonl/transform"
        autoload :StandardAdapter,
                 "lutaml/key_value/adapter/jsonl/standard_adapter"
      end
    end
  end
end
