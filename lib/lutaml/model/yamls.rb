# frozen_string_literal: true

module Lutaml
  module Model
    module Yamls
    end
  end
end

require_relative "yamls/standard_adapter"
require_relative "yamls/document"
require_relative "yamls/mapping"
require_relative "yamls/mapping_rule"
require_relative "yamls/transform"

Lutaml::Model::FormatRegistry.register(
  :yamls,
  mapping_class: Lutaml::Model::Yamls::Mapping,
  adapter_class: Lutaml::Model::Yamls::StandardAdapter,
  transformer: Lutaml::Model::Yamls::Transform,
)
