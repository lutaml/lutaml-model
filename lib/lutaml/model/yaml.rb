# frozen_string_literal: true

# Backward compatibility - provides Lutaml::Model::Yaml namespace as alias to Lutaml::Yaml

module Lutaml
  module Model
    module Yaml
      StandardAdapter = ::Lutaml::Yaml::Adapter::StandardAdapter
      Document = ::Lutaml::Yaml::Adapter::Document
      Mapping = ::Lutaml::Yaml::Adapter::Mapping
      MappingRule = ::Lutaml::Yaml::Adapter::MappingRule
      Transform = ::Lutaml::Yaml::Adapter::Transform
    end
  end
end