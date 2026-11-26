# frozen_string_literal: true

module Lutaml
  module Lml
    class InstancesExport < Lutaml::Model::Serializable
      attribute :format_type, :string
      attribute :attributes, "Lutaml::Lml::TopElementAttribute", collection: true, default: []
    end
  end
end
