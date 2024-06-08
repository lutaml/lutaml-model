# ceramic.rb
require "lutaml/model"
require_relative "glaze"

class Ceramic < Lutaml::Model::Serializable
  attribute :type, Lutaml::Model::Type::String
  attribute :glaze, Glaze

  yaml do
    map "type", to: :type
    map "color", to: :color, delegate: :glaze
    map "finish", to: :finish, delegate: :glaze
  end
end

# ceramic = Ceramic.from_yaml(<<~DATA)
#   type: Vase
# color: Blue
# finish: Glossy
# DATA

# puts ceramic.glaze.color
# # => Blue

# puts ceramic.color
# # => Blue
