# frozen_string_literal: true

require "lutaml/model"
require_relative "lml_mapping_fixtures"

# Named source models for the LML import/export round-trip specs
# (lutaml-model#1033 card 03c). The graph mixes namespaces, nested and
# collection models, ordered/mixed content and discriminator-based
# polymorphism in all three wire formats.
module LmlImportFixtures
  class Animal < Lutaml::Model::Serializable
    attribute :kind, :string, polymorphic_class: true
    attribute :name, :string

    xml do
      element "animal"
      map_attribute "kind", to: :kind
      map_element "name", to: :name
    end
    json do
      map "kind", to: :kind
      map "name", to: :name
    end
  end

  class Dog < Animal
  end

  class Kennel < Lutaml::Model::Serializable
    attribute :animals, Animal, collection: true
    attribute :owner, :string

    xml do
      element "kennel"
      map_element "animal", to: :animals, polymorphic: {
        attribute: "kind", class_map: { "dog" => "LmlImportFixtures::Dog", "animal" => "LmlImportFixtures::Animal" }
      }
      map_element "owner", to: :owner
    end
    json do
      map "animals", to: :animals, polymorphic: {
        attribute: "kind", class_map: { "dog" => "LmlImportFixtures::Dog", "animal" => "LmlImportFixtures::Animal" }
      }
      map "owner", to: :owner
    end
  end

  GRAPH_ROOTS = [
    LmlMappingFixtures::Doc, LmlMappingFixtures::Shape,
    LmlOrderFixtures::Para, LmlOrderFixtures::Transport, Kennel
  ].freeze
end
