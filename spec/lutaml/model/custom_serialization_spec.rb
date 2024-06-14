# spec/lutaml/model/custom_serialization_spec.rb
require "spec_helper"
require "lutaml/model"

class CustomSerialization < Lutaml::Model::Serializable
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

RSpec.describe CustomSerialization do
  let(:attributes) {
    {
      name: "Vase",
      size: 12,
    }
  }
  let(:model) { CustomSerialization.new(attributes) }

  it "serializes to JSON with custom methods" do
    expected_json = {
      name: "Masterpiece: Vase",
      size: 12,
    }.to_json

    expect(model.to_json).to eq(expected_json)
  end

  it "deserializes from JSON with custom methods" do
    json = {
      name: "Masterpiece: Vase",
      size: 12,
    }.to_json

    ceramic = CustomSerialization.from_json(json)
    expect(ceramic.name).to eq("Vase")
    expect(ceramic.size).to eq(12)
  end
end
