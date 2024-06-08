# building.rb
require "lutaml/model"

class Building < Lutaml::Model::Serializable
  attribute :name, Lutaml::Model::Type::String, default: -> { "my_building" }
  attribute :room_name, Lutaml::Model::Type::String, collection: true

  xml do
    map_attribute "name", to: :name
    map_element "room_name", to: :room_name
  end

  json do
    map_element "name", to: :name
    map_element "room_name", to: :room_name
  end
end
