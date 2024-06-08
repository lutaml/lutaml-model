# custom_ceramic.rb
require "lutaml/model"

class CustomCeramic < Lutaml::Model::Serializable
  attribute :name, Lutaml::Model::Type::String
  attribute :size, Lutaml::Model::Type::Integer

  json do
    map "name", to: :name, with: { to: :name_to_json, from: :name_from_json }
    map "size", to: :size
  end

  def name_to_json(model, value)
    "Masterpiece: #{value}"
  end

  def name_from_json(model, doc)
    doc["name"].sub("Masterpiece: ", "")
  end
end

# ceramic = CustomCeramic.new(name: "Vase", size: 12)
# json = ceramic.to_json
# puts json
# # => {"name":"Masterpiece: Vase","size":12}

# ceramic_from_json = CustomCeramic.from_json(json)
# puts ceramic_from_json.name
# # => Vase
