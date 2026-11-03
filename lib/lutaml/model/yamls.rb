# frozen_string_literal: true

# Backward compatibility - provides Lutaml::Model::Yamls namespace as alias to Lutaml::Yamls

module Lutaml
  module Model
    module Yamls
      StandardAdapter = ::Lutaml::Yamls::Adapter::StandardAdapter
      YeptrisAdapter = ::Lutaml::Yamls::Adapter::YeptrisAdapter
      Document = ::Lutaml::Yamls::Adapter::Document
      Mapping = ::Lutaml::Yamls::Adapter::Mapping
      MappingRule = ::Lutaml::Yamls::Adapter::MappingRule
      Transform = ::Lutaml::Yamls::Adapter::Transform
    end
  end
end
