# frozen_string_literal: true

module Lutaml
  module Lml
    class Group < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :values, :string, collection: true
      attribute :groups, "Lutaml::Lml::Group", collection: true
    end
  end
end
