# frozen_string_literal: true

module Lutaml
  module Model
    module Jsonl
    end
  end
end

require_relative "jsonl/standard_adapter"
require_relative "jsonl/document"
require_relative "jsonl/mapping"
require_relative "jsonl/mapping_rule"
require_relative "jsonl/transform"

Lutaml::Model::FormatRegistry.register(
  :jsonl,
  mapping_class: Lutaml::Model::Jsonl::Mapping,
  adapter_class: Lutaml::Model::Jsonl::StandardAdapter,
  transformer: Lutaml::Model::Jsonl::Transform,
)
