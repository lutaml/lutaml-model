# pottery.rb
require "lutaml/model"

class Pottery < Lutaml::Model::Serializable
  attribute :name, Lutaml::Model::Type::String, default: -> { "Unnamed Pottery" }
  attribute :clay_type, Lutaml::Model::Type::String
  attribute :glaze, Lutaml::Model::Type::String
  attribute :dimensions, Lutaml::Model::Type::String, collection: true

  xml do
    root "pottery"

    map_element "name", to: :name, render_nil: true
    map_element "clay_type", to: :clay_type, render_nil: false
    map_element "glaze", to: :glaze, render_nil: true
    map_element "dimensions", to: :dimensions, render_nil: false
  end

  yaml do
    map "name", to: :name, render_nil: true
    map "clay_type", to: :clay_type, render_nil: false
    map "glaze", to: :glaze, render_nil: true
    map "dimensions", to: :dimensions, render_nil: false
  end

  json do
    map_element "name", to: :name, render_nil: true
    map_element "clay_type", to: :clay_type, render_nil: false
    map_element "glaze", to: :glaze, render_nil: true
    map_element "dimensions", to: :dimensions, render_nil: false
  end

  toml do
    map_element "name", to: :name, render_nil: true
    map_element "clay_type", to: :clay_type, render_nil: false
    map_element "glaze", to: :glaze, render_nil: true
    map_element "dimensions", to: :dimensions, render_nil: false
  end
end
