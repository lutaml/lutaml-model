# frozen_string_literal: true

require_relative "model"
require_relative "rdf"

module Lutaml
  module JsonLd
    autoload :Adapter, "#{__dir__}/jsonld/adapter"
  end
end

Lutaml::Model::FormatRegistry.register(
  :jsonld,
  mapping_class: Lutaml::Rdf::Mapping,
  adapter_class: Lutaml::JsonLd::Adapter,
  transformer: Lutaml::Rdf::LinkedDataTransform,
  key_value: false,
  rdf: true,
  error_types: ["JSON::ParserError"],
)
