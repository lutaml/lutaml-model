# kiln.rb
require "lutaml/model"

class Kiln < Lutaml::Model::Serializable
  attribute :brand, Lutaml::Model::Type::String
  attribute :capacity, Lutaml::Model::Type::Float
  attribute :firing, Lutaml::Model::Type::String

  json do
    map "brand", to: :brand
    map "capacity", to: :capacity
    map "firing", to: :firing
  end

  yaml do
    map "brand", to: :brand
    map "capacity", to: :capacity
    map "firing", to: :firing
  end

  toml do
    map "brand", to: :brand
    map "capacity", to: :capacity
    map "firing", to: :firing
  end

  xml do
    root "kiln"
    map_element "firing", to: :firing
    map_attribute "brand", to: :brand
    map_element "capacity", to: :capacity
  end
end
