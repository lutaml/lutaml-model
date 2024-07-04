# spec/fixtures/address.rb
require "lutaml/model"
require_relative "persons"

class Address < Lutaml::Model::Serializable
  attribute :country, Lutaml::Model::Type::String
  attribute :post_code, Lutaml::Model::Type::String
  attribute :persons, Persons

  json do
    map "country", to: :country
    map "postCode", to: :post_code
    map "persons", to: :persons
  end

  xml do
    root "Address"
    map_element "Country", to: :country
    map_element "PostCode", to: :post_code
    map_element "Persons", to: :persons
  end

  yaml do
    map "country", to: :country
    map "postCode", to: :post_code
    map "persons", to: :persons
  end

  toml do
    map "country", to: :country
    map "post_code", to: :post_code
    map "persons", to: :persons
  end
end
