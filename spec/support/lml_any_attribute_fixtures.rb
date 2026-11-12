# frozen_string_literal: true

require "lutaml/model"

# Named fixtures for LML any_attribute (map_all_attributes) specs.
module LmlAnyAttributeFixtures
  class Tag < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :other_attributes, :hash

    xml do
      element "tag"
      map_attribute "id", to: :id
      map_all_attributes to: :other_attributes
    end
  end

  class Filtered < Lutaml::Model::Serializable
    attribute :other_attributes, :hash

    xml do
      element "filtered"
      map_all_attributes to: :other_attributes, matching: /\Adata-/
    end
  end
end
