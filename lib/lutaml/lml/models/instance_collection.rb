# frozen_string_literal: true

module Lutaml
  module Lml
    # A named instances collection with its instances and imports/exports.
    class InstanceCollection < Lutaml::Model::Serializable
      include Lutaml::Lml::Positioned

      attribute :name, :string
      attribute :instances, "Lutaml::Lml::Instance", collection: true, default: []
      attribute :imports, "Lutaml::Lml::InstancesImport", collection: true, default: []
      attribute :exports, "Lutaml::Lml::InstancesExport", collection: true, default: []
      attribute :collections, "Lutaml::Lml::Collection", collection: true, default: []
    end
  end
end
