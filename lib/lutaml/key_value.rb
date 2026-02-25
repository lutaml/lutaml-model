# frozen_string_literal: true

require "lutaml/model"

module Lutaml
  module KeyValue
    autoload :DataModel, "lutaml/key_value/data_model"
    autoload :Document, "lutaml/key_value/document"
    autoload :Mapping, "lutaml/key_value/mapping"
    autoload :MappingRule, "lutaml/key_value/mapping_rule"
    autoload :Transform, "lutaml/key_value/transform"
    autoload :Transformation, "lutaml/key_value/transformation"
    autoload :TransformationBuilder, "lutaml/key_value/transformation_builder"
    autoload :Adapter, "lutaml/key_value/adapter"
  end
end
