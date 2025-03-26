# frozen_string_literal: true

module Lutaml
  module Model
    module HashAdapter
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
  mapping_class: Lutaml::Model::HashAdapter::Mapping,
  adapter_class: Lutaml::Model::HashAdapter::StandardAdapter,
  transformer: Lutaml::Model::HashAdapter::Transform,
)
