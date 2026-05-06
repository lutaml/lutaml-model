# frozen_string_literal: true

require_relative "model"
require_relative "rdf"

module Lutaml
  module JsonLd
    autoload :Context, "#{__dir__}/jsonld/context"
    autoload :TermDefinition, "#{__dir__}/jsonld/term_definition"
    autoload :Transform, "#{__dir__}/jsonld/transform"
    autoload :Adapter, "#{__dir__}/jsonld/adapter"
  end
end

Lutaml::Model::FormatRegistry.register(
  :jsonld,
  mapping_class: Lutaml::Rdf::Mapping,
  adapter_class: Lutaml::JsonLd::Adapter,
  transformer: Lutaml::JsonLd::Transform,
  key_value: false,
  rdf: true,
  error_types: ["JSON::ParserError"],
)
