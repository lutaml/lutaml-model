# spec/fixtures/person.rb
require "lutaml/model"

class Person < Lutaml::Model::Serializable
  attribute :first_name, Lutaml::Model::Type::String
  attribute :last_name, Lutaml::Model::Type::String
  attribute :age, Lutaml::Model::Type::Integer
  attribute :height, Lutaml::Model::Type::Float
  attribute :birthdate, Lutaml::Model::Type::Date
  attribute :last_login, Lutaml::Model::Type::DateTime
  attribute :wakeup_time, Lutaml::Model::Type::Time
  attribute :active, Lutaml::Model::Type::Boolean

  xml do
    root(name: "Person", namespace: "http://example.com/person", prefix: "p")
    map_element(name: "FirstName", to: :first_name, namespace: "http://example.com/person", prefix: "p")
    map_element(name: "LastName", to: :last_name, namespace: "http://example.com/person", prefix: "p")
    map_element(name: "Age", to: :age)
    map_element(name: "Height", to: :height)
    map_element(name: "Birthdate", to: :birthdate)
    map_element(name: "LastLogin", to: :last_login)
    map_element(name: "WakeupTime", to: :wakeup_time)
    map_element(name: "Active", to: :active)
  end

  yaml do
    map_element "firstName", to: :first_name
    map_element "lastName", with: { to: :yaml_from_last_name, from: :yaml_to_last_name }
  end

  def yaml_from_last_name(yaml_builder, model)
    yaml_builder[:last_name] = model.last_name
  end

  def yaml_to_last_name(from_yaml, model)
    model.last_name = from_yaml[:lastName]
  end
end
