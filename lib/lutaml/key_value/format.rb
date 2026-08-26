# frozen_string_literal: true

# Internal KeyValue implementation. Loaded from lib/lutaml/key_value.rb
# (the public entrypoint) and from lib/lutaml/model.rb (so the model
# entrypoint triggers the registration side effects).
# No require_relative "model" here — keeps the require graph acyclic.

module Lutaml
  module KeyValue
    autoload :DataModel, "#{__dir__}/data_model"
    autoload :Document, "#{__dir__}/document"
    autoload :Mapping, "#{__dir__}/mapping"
    autoload :MappingRule, "#{__dir__}/mapping_rule"
    autoload :Transform, "#{__dir__}/transform"
    autoload :Transformation, "#{__dir__}/transformation"
    autoload :TransformationBuilder, "#{__dir__}/transformation_builder"
    autoload :Adapter, "#{__dir__}/adapter"
  end
end

# Register KeyValue transformation builders for all key-value formats
%i[json yaml toml hash].each do |format|
  Lutaml::Model::TransformationRegistry.register_builder(
    format, Lutaml::KeyValue::TransformationBuilder
  )
end
