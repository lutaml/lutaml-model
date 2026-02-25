# frozen_string_literal: true

module Lutaml
  module KeyValue
    module Adapter
      module HashAdapter
        autoload :Document, "lutaml/key_value/adapter/hash/document"
        autoload :Mapping, "lutaml/key_value/adapter/hash/mapping"
        autoload :MappingRule, "lutaml/key_value/adapter/hash/mapping_rule"
        autoload :Transform, "lutaml/key_value/adapter/hash/transform"
        autoload :StandardAdapter,
                 "lutaml/key_value/adapter/hash/standard_adapter"
      end
    end
  end
end
