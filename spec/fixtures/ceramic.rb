# ceramic.rb
require "lutaml/model"
require_relative "glaze"

class Ceramic < Lutaml::Model::Serializable
  attribute :type, Lutaml::Model::Type::String
  attribute :glaze, Glaze

  json do
    map "type", to: :type
    map "color", to: :color, delegate: :glaze
    map "finish", to: :finish, delegate: :glaze
  end

  yaml do
    map "type", to: :type
    map "color", to: :color, delegate: :glaze
    map "finish", to: :finish, delegate: :glaze
  end

  toml do
    map "type", to: :type
    map "color", to: :color, delegate: :glaze
    map "finish", to: :finish, delegate: :glaze
  end

  xml do
    root "ceramic"
    map_element "type", to: :type
    map_element "color", to: :color, delegate: :glaze
    map_element "finish", to: :finish, delegate: :glaze
  end
end

# ceramic = Ceramic.from_yaml(<<~DATA)
# type: Vase
# color: Blue
# finish: Glossy
# DATA

# puts ceramic.glaze.color
# # => Blue

# puts ceramic.color
# # => Blue

# puts ceramic.to_json(only: [:type, glaze: [:color]], pretty: true)
# # => {
# #      "type": "Vase",
# #      "color": "Blue"
# #    }

# puts ceramic.to_xml(pretty: true)
# # => <ceramic>
# #      <type>Vase</type>
# #      <color>Blue</color>
# #      <finish>Glossy</finish>
# #    </ceramic>
