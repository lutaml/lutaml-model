# frozen_string_literal: true

module Lutaml
  module Yamls
    module Adapter
      autoload :Document, "#{__dir__}/adapter/document"
      autoload :Mapping, "#{__dir__}/adapter/mapping"
      autoload :MappingRule, "#{__dir__}/adapter/mapping_rule"
      autoload :Transform, "#{__dir__}/adapter/transform"
      autoload :YamlsSequence, "#{__dir__}/adapter/yamls_sequence"
      autoload :YamlsSequenceRule, "#{__dir__}/adapter/yamls_sequence_rule"
      autoload :StandardAdapter, "#{__dir__}/adapter/standard_adapter"
    end
  end
end
