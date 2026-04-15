# frozen_string_literal: true

# Backward compatibility - provides Lutaml::Model::Json namespace as alias to Lutaml::Json

module Lutaml
  module Model
    module Json
      StandardAdapter = ::Lutaml::Json::Adapter::StandardAdapter
      Document = ::Lutaml::Json::Adapter::Document
      Mapping = ::Lutaml::Json::Adapter::Mapping
      MappingRule = ::Lutaml::Json::Adapter::MappingRule
      Transform = ::Lutaml::Json::Adapter::Transform
      OjAdapter = ::Lutaml::Json::Adapter::OjAdapter
      MultiJsonAdapter = ::Lutaml::Json::Adapter::MultiJsonAdapter
    end
  end
end
