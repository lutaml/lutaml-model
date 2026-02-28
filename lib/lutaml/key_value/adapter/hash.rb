# frozen_string_literal: true

module Lutaml
  module KeyValue
    module Adapter
      module Hash
        autoload :Document, "#{__dir__}/hash/document"
        autoload :Mapping, "#{__dir__}/hash/mapping"
        autoload :MappingRule, "#{__dir__}/hash/mapping_rule"
        autoload :Transform, "#{__dir__}/hash/transform"
        autoload :StandardAdapter, "#{__dir__}/hash/standard_adapter"
      end
    end
  end
end
