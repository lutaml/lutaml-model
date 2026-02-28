# frozen_string_literal: true

require "lutaml/model"

module Lutaml
  module KeyValue
    autoload :DataModel, "#{__dir__}/key_value/data_model"
    autoload :Document, "#{__dir__}/key_value/document"
    autoload :Mapping, "#{__dir__}/key_value/mapping"
    autoload :MappingRule, "#{__dir__}/key_value/mapping_rule"
    autoload :Transform, "#{__dir__}/key_value/transform"
    autoload :Transformation, "#{__dir__}/key_value/transformation"
    autoload :TransformationBuilder, "#{__dir__}/key_value/transformation_builder"
    autoload :Adapter, "#{__dir__}/key_value/adapter"
  end
end
