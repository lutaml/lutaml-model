# frozen_string_literal: true

module Lutaml
  module Lml
    module Format
      module Adapter
        autoload :Document, "lutaml/lml/format/adapter/document"
        autoload :Mapping, "lutaml/lml/format/adapter/mapping"
        autoload :Transform, "lutaml/lml/format/adapter/transform"
        autoload :StandardAdapter, "lutaml/lml/format/adapter/standard_adapter"
      end
    end
  end
end

# ExportTransformer is defined at Lutaml::Model::ExportTransformer but
# referenced as bare ExportTransformer from KeyValue::Transform. Bridge the gap
# so constant resolution succeeds for the :lml format's to_lml path.
unless Lutaml::KeyValue.const_defined?(:ExportTransformer)
  Lutaml::KeyValue::ExportTransformer = Lutaml::Model::ExportTransformer
end

Lutaml::Model::FormatRegistry.register(
  :lml,
  mapping_class: Lutaml::Lml::Format::Adapter::Mapping,
  adapter_class: Lutaml::Lml::Format::Adapter::StandardAdapter,
  transformer: Lutaml::Lml::Format::Adapter::Transform,
  key_value: true,
)
