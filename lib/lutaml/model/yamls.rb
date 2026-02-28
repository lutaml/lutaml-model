# frozen_string_literal: true

# YAMLS format entry point - uses Lutaml::KeyValue::Adapter::Yamls namespace
# Constants are accessed via autoload from key_value/adapter/yamls.rb

# Backward compatibility alias
module Lutaml
  module Model
    module Yamls
      StandardAdapter = Lutaml::KeyValue::Adapter::Yamls::StandardAdapter
      Document = Lutaml::KeyValue::Adapter::Yamls::Document
      Mapping = Lutaml::KeyValue::Adapter::Yamls::Mapping
      MappingRule = Lutaml::KeyValue::Adapter::Yamls::MappingRule
      Transform = Lutaml::KeyValue::Adapter::Yamls::Transform
    end
  end
end

Lutaml::Model::FormatRegistry.register(
  :yamls,
  mapping_class: Lutaml::KeyValue::Adapter::Yamls::Mapping,
  adapter_class: Lutaml::KeyValue::Adapter::Yamls::StandardAdapter,
  transformer: Lutaml::KeyValue::Adapter::Yamls::Transform,
)
