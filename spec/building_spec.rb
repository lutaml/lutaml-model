# spec/building_spec.rb
require "spec_helper"
require_relative "fixtures/building"

RSpec.describe Building do
  let(:attributes) {
    {
      name: "my_building",
      room_name: ["Living Room", "Kitchen"],
    }
  }
  let(:model) { Building.new(attributes) }

  it "serializes to JSON with default mappings" do
    expected_json = {
      name: "my_building",
      room_name: ["Living Room", "Kitchen"],
    }.to_json

    expect(model.to_json).to eq(expected_json)
  end

  it "deserializes from JSON with default mappings" do
    json = attributes.to_json
    building = Building.from_json(json)
    expect(building.name).to eq("my_building")
    expect(building.room_name).to eq(["Living Room", "Kitchen"])
  end

  it "serializes to XML with default mappings" do
    expected_xml = Nokogiri::XML::Builder.new do |xml|
      xml.building {
        xml.name "my_building"
        xml.room_name "Living Room"
        xml.room_name "Kitchen"
      }
    end.to_xml

    expect(Nokogiri::XML(model.to_xml).to_s).to eq(Nokogiri::XML(expected_xml).to_s)
  end

  it "deserializes from XML with default mappings" do
    xml = Nokogiri::XML::Builder.new do |xml|
      xml.building {
        xml.name "my_building"
        xml.room_name "Living Room"
        xml.room_name "Kitchen"
      }
    end.to_xml

    building = Building.from_xml(xml)
    expect(building.name).to eq("my_building")
    expect(building.room_name).to eq(["Living Room", "Kitchen"])
  end

  let(:attributes_yaml) {
    {
      "name" => "my_building",
      "room_name" => ["Living Room", "Kitchen"],
    }
  }
  it "serializes to YAML with default mappings" do
    expect(model.to_yaml).to eq(attributes_yaml.to_yaml)
  end

  it "deserializes from YAML with default mappings" do
    yaml = attributes_yaml.to_yaml
    building = Building.from_yaml(yaml)
    expect(building.name).to eq("my_building")
    expect(building.room_name).to eq(["Living Room", "Kitchen"])
  end
end
