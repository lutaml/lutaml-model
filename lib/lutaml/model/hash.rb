# frozen_string_literal: true

# Backward compatibility - provides Lutaml::Model::Hash namespace as alias to Lutaml::HashFormat

module Lutaml
  module Model
    module Hash
      StandardAdapter = ::Lutaml::HashFormat::Adapter::StandardAdapter
      Document = ::Lutaml::HashFormat::Adapter::Document
      Mapping = ::Lutaml::HashFormat::Adapter::Mapping
      MappingRule = ::Lutaml::HashFormat::Adapter::MappingRule
      Transform = ::Lutaml::HashFormat::Adapter::Transform
    end
  end
end
