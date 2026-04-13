# frozen_string_literal: true

# Backward compatibility - provides Lutaml::Model::Jsonl namespace as alias to Lutaml::Jsonl

module Lutaml
  module Model
    module Jsonl
      StandardAdapter = ::Lutaml::Jsonl::Adapter::StandardAdapter
      Document = ::Lutaml::Jsonl::Adapter::Document
      Mapping = ::Lutaml::Jsonl::Adapter::Mapping
      MappingRule = ::Lutaml::Jsonl::Adapter::MappingRule
      Transform = ::Lutaml::Jsonl::Adapter::Transform
    end
  end
end