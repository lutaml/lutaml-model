# frozen_string_literal: true

module Lutaml
  module Model
    module Json
    end
  end
end

require_relative "json/standard_adapter"
require_relative "json/document"
require_relative "json/mapping"
require_relative "json/mapping_rule"
require_relative "json/transform"

Lutaml::Model::FormatRegistry.register(
  :json,
  mapping_class: Lutaml::Model::Json::Mapping,
  adapter_class: Lutaml::Model::Json::StandardAdapter,
  transformer: Lutaml::Model::Json::Transform,
)
