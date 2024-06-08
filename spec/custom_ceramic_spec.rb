# spec/custom_ceramic_spec.rb
require "spec_helper"
require_relative "fixtures/custom_ceramic"

RSpec.describe CustomCeramic do
  let(:attributes) {
    {
      name: "Vase",
      size: 12,
    }
  }
  let(:model) { CustomCeramic.new(attributes) }

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

    ceramic = CustomCeramic.from_json(json)
    expect(ceramic.name).to eq("Vase")
    expect(ceramic.size).to eq(12)
  end
end
