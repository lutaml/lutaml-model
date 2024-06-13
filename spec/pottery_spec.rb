# spec/pottery_spec.rb
require "spec_helper"
require_relative "fixtures/pottery"

RSpec.describe Pottery do
  let(:attributes) {
    {
      name: nil,
      clay_type: nil,
      glaze: nil,
      dimensions: nil,
    }
  }
  let(:model) { Pottery.new(attributes) }

  it "serializes to JSON with render_nil option" do
    expected_json = {
      name: nil,
      clay_type: nil,
      glaze: nil,
      dimensions: nil,
    }.to_json

    expect(model.to_json).to eq(expected_json)
  end

  it "deserializes from JSON with render_nil option" do
    json = attributes.to_json
    pottery = Pottery.from_json(json)
    expect(pottery.name).to be_nil
    expect(pottery.clay_type).to be_nil
    expect(pottery.glaze).to be_nil
    expect(pottery.dimensions).to be_nil
  end

  it "serializes to XML with render_nil option" do
    expected_xml = <<~XML
      <pottery>
        <name/>
        <glaze/>
      </pottery>
    XML

    expect(model.to_xml).to be_equivalent_to(expected_xml)
  end

  it "deserializes from XML with render_nil option" do
    xml = <<~XML
      <pottery>
        <name/>
        <glaze/>
      </pottery>
    XML

    pottery = Pottery.from_xml(xml)
    expect(pottery.name).to be_nil
    expect(pottery.glaze).to be_nil
  end

  it "serializes to YAML with render_nil option" do
    expected_yaml = <<-YAML
---
name:
glaze:
    YAML

    expect(model.to_yaml.strip).to eq(expected_yaml.strip)
  end

  it "deserializes from YAML with render_nil option" do
    yaml = <<-YAML
---
name:
glaze:
    YAML

    pottery = Pottery.from_yaml(yaml)
    expect(pottery.name).to eq("Unnamed Pottery")
    expect(pottery.glaze).to be_nil
  end
end
