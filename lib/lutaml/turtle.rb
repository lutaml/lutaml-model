# frozen_string_literal: true

require_relative "model"
require_relative "rdf"

module Lutaml
  module Turtle
    autoload :Mapping, "#{__dir__}/turtle/mapping"
    autoload :Transform, "#{__dir__}/turtle/transform"
    autoload :Adapter, "#{__dir__}/turtle/adapter"
  end
end

Lutaml::Model::FormatRegistry.register(
  :turtle,
  mapping_class: Lutaml::Turtle::Mapping,
  adapter_class: Lutaml::Turtle::Adapter,
  transformer: Lutaml::Turtle::Transform,
  key_value: false,
  rdf: true,
  error_types: ["RDF::ReaderError"],
)
