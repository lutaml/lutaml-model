# frozen_string_literal: true

require "json"

module Lutaml
  module KeyValue
    module Adapter
      module Jsonl
        autoload :Document, "#{__dir__}/jsonl/document"
        autoload :Mapping, "#{__dir__}/jsonl/mapping"
        autoload :MappingRule, "#{__dir__}/jsonl/mapping_rule"
        autoload :Transform, "#{__dir__}/jsonl/transform"
        autoload :StandardAdapter, "#{__dir__}/jsonl/standard_adapter"
      end
    end
  end
end
