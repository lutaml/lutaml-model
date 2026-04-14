# frozen_string_literal: true

module Lutaml
  module KeyValue
    autoload :DataModel, "#{__dir__}/key_value/data_model"
    autoload :Document, "#{__dir__}/key_value/document"
    autoload :Mapping, "#{__dir__}/key_value/mapping"
    autoload :MappingRule, "#{__dir__}/key_value/mapping_rule"
    autoload :Transform, "#{__dir__}/key_value/transform"
    autoload :Transformation, "#{__dir__}/key_value/transformation"
    autoload :TransformationBuilder,
             "#{__dir__}/key_value/transformation_builder"
    autoload :Adapter, "#{__dir__}/key_value/adapter"
  end
end

require_relative "model"

# Register KeyValue transformation builders for all key-value formats
%i[json yaml toml hash].each do |format|
  Lutaml::Model::TransformationRegistry.register_builder(
    format, Lutaml::KeyValue::TransformationBuilder
  )
end
