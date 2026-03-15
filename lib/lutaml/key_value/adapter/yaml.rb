# frozen_string_literal: true

require "yaml"

module Lutaml
  module KeyValue
    module Adapter
      module Yaml
        autoload :Document, "#{__dir__}/yaml/document"
        autoload :Mapping, "#{__dir__}/yaml/mapping"
        autoload :MappingRule, "#{__dir__}/yaml/mapping_rule"
        autoload :Transform, "#{__dir__}/yaml/transform"
        autoload :StandardAdapter, "#{__dir__}/yaml/standard_adapter"
      end
    end
  end
end
