# frozen_string_literal: true

# JSON format entry point
# Provides Lutaml::Json namespace helpers before exposing Model aliases

require_relative "../json"

# Backward compatibility - provides Lutaml::Model::Json namespace as alias to Lutaml::Json

module Lutaml
  module Model
    module Json
      StandardAdapter = ::Lutaml::Json::Adapter::StandardAdapter
      Document = ::Lutaml::Json::Adapter::Document
      Mapping = ::Lutaml::Json::Adapter::Mapping
      MappingRule = ::Lutaml::Json::Adapter::MappingRule
      Transform = ::Lutaml::Json::Adapter::Transform
      Lutaml::Model::RuntimeCompatibility.define_native_aliases(
        self,
        OjAdapter: "::Lutaml::Json::Adapter::OjAdapter",
        MultiJsonAdapter: "::Lutaml::Json::Adapter::MultiJsonAdapter",
      )
    end
  end
end
