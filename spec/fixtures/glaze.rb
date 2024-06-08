# glaze.rb
require "lutaml/model"

class Glaze < Lutaml::Model::Serializable
  attribute :color, Lutaml::Model::Type::String
  attribute :finish, Lutaml::Model::Type::String
end
