# frozen_string_literal: true

module Lutaml
  module Json
    module Adapter
      autoload :Document, "#{__dir__}/adapter/document"
      autoload :Mapping, "#{__dir__}/adapter/mapping"
      autoload :MappingRule, "#{__dir__}/adapter/mapping_rule"
      autoload :Transform, "#{__dir__}/adapter/transform"
      autoload :StandardAdapter, "#{__dir__}/adapter/standard_adapter"
      autoload :OjAdapter, "#{__dir__}/adapter/oj_adapter"
      autoload :MultiJsonAdapter, "#{__dir__}/adapter/multi_json_adapter"
    end
  end
end
