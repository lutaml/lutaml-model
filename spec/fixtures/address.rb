# spec/fixtures/address.rb
require "lutaml/model"
require_relative "person"

class Address < Lutaml::Model::Serializable
  attribute :country, Lutaml::Model::Type::String
  attribute :post_code, Lutaml::Model::Type::String
  attribute :persons, Person, collection: true

  json do
    map_element "country", to: :country
    map_element "postCode", to: :post_code
    map_element "persons", to: :persons
  end

  xml do
    root "Address"
    map_element "Country", to: :country
    map_element "PostCode", to: :post_code
    map_element "Persons", to: :persons
  end
end
