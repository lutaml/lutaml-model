# frozen_string_literal: true

require "json"

module Lutaml
  module KeyValue
    module Adapter
      module Json
        autoload :Document, "#{__dir__}/json/document"
        autoload :Mapping, "#{__dir__}/json/mapping"
        autoload :MappingRule, "#{__dir__}/json/mapping_rule"
        autoload :Transform, "#{__dir__}/json/transform"
        autoload :StandardAdapter, "#{__dir__}/json/standard_adapter"
        autoload :OjAdapter, "#{__dir__}/json/oj_adapter"
        autoload :MultiJsonAdapter, "#{__dir__}/json/multi_json_adapter"
      end
    end
  end
end
