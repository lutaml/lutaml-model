# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
    end
  end
end

require_relative "xml/document"
require_relative "xml/mapping"
require_relative "xml/mapping_rule"
require_relative "xml/transform"

Lutaml::Model::FormatRegistry.register(
  :xml,
  mapping_class: Lutaml::Model::Xml::Mapping,
  adapter_class: nil,
  transformer: Lutaml::Model::Xml::Transform,
)
