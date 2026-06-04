# frozen_string_literal: true

require_relative "model"
require_relative "rdf"
require_relative "yaml"

module Lutaml
  module YamlLd
    autoload :Adapter, "#{__dir__}/yamlld/adapter"
  end
end

# Known limitations (v1):
# - Single YAML document only; multi-document streams not interpreted as @graph.
# - YAML anchors/aliases not used to deduplicate @id references.
# - External @context loading not performed (matches :jsonld behavior).
Lutaml::Model::FormatRegistry.register(
  :yamlld,
  mapping_class: Lutaml::Rdf::Mapping,
  adapter_class: Lutaml::YamlLd::Adapter,
  transformer: Lutaml::Rdf::LinkedDataTransform,
  key_value: false,
  rdf: true,
  error_types: ["Psych::SyntaxError"],
)
