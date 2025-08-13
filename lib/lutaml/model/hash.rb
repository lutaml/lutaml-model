# frozen_string_literal: true

module Lutaml
  module Model
    module Hash
    end
  end
end

require_relative "hash/standard_adapter"
require_relative "hash/document"
require_relative "hash/mapping"
require_relative "hash/mapping_rule"
require_relative "hash/transform"

Lutaml::Model::FormatRegistry.register(
  :hash,
  mapping_class: Lutaml::Model::Hash::Mapping,
  adapter_class: Lutaml::Model::Hash::StandardAdapter,
  transformer: Lutaml::Model::Hash::Transform,
)
