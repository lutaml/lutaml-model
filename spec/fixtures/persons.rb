# spec/fixtures/address.rb
require "lutaml/model"
require_relative "person"

class Persons < Lutaml::Model::Serializable
  attribute :person, Person, collection: true

  json do
    map "person", to: :person
  end

  xml do
    root "Persons"

    map_element "Person", to: :person
  end

  yaml do
    map "person", to: :person
  end

  toml do
    map "person", to: :person
  end
end
