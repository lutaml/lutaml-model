# frozen_string_literal: true

require "yaml"

module Lutaml
  module KeyValue
    module Adapter
      module Yamls
        autoload :Document, "#{__dir__}/yamls/document"
        autoload :Mapping, "#{__dir__}/yamls/mapping"
        autoload :MappingRule, "#{__dir__}/yamls/mapping_rule"
        autoload :Transform, "#{__dir__}/yamls/transform"
        autoload :StandardAdapter, "#{__dir__}/yamls/standard_adapter"
      end
    end
  end
end
