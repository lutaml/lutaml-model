# spec/lutaml/model/render_nil_spec.rb
require "spec_helper"
require "lutaml/model"

class RenderNil < Lutaml::Model::Serializable
  attribute :name, Lutaml::Model::Type::String, default: -> { "Unnamed Pottery" }
  attribute :clay_type, Lutaml::Model::Type::String
  attribute :glaze, Lutaml::Model::Type::String
  attribute :dimensions, Lutaml::Model::Type::String, collection: true

  json do
    map "name", to: :name, render_nil: true
    map "clay_type", to: :clay_type, render_nil: true
    map "glaze", to: :glaze, render_nil: true
    map "dimensions", to: :dimensions, render_nil: false
  end

  xml do
    root "render_nil"
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

  toml do
    map "name", to: :name, render_nil: true
    map "clay_type", to: :clay_type, render_nil: false
    map "glaze", to: :glaze, render_nil: true
    map "dimensions", to: :dimensions, render_nil: false
  end
end

RSpec.describe RenderNil do
  let(:attributes) {
    {
      name: nil,
      clay_type: nil,
      glaze: nil,
      dimensions: nil,
    }
  }
  let(:model) { RenderNil.new(attributes) }

  it "serializes to JSON with render_nil option" do
    expected_json = {
      name: nil,
      clay_type: nil,
      glaze: nil,
      dimensions: [],
    }.to_json

    expect(model.to_json).to eq(expected_json)
  end

  it "deserializes from JSON with render_nil option" do
    json = attributes.to_json
    pottery = RenderNil.from_json(json)
    expect(pottery.name).to be_nil
    expect(pottery.clay_type).to be_nil
    expect(pottery.glaze).to be_nil
    expect(pottery.dimensions).to eq([])
  end

  it "serializes to XML with render_nil option" do
    expected_xml = <<~XML
      <render_nil>
        <name/>
        <glaze/>
      </render_nil>
    XML

    expect(model.to_xml).to be_equivalent_to(expected_xml)
  end

  it "deserializes from XML with render_nil option" do
    xml = <<~XML
      <render_nil>
        <name/>
        <glaze/>
      </render_nil>
    XML

    pottery = RenderNil.from_xml(xml)
    expect(pottery.name).to be_nil
    expect(pottery.glaze).to be_nil
  end

  it "serializes to YAML with render_nil option" do
    expected_yaml = <<~YAML
      ---
      name:
      glaze:
      dimensions: []
    YAML

    expect(model.to_yaml.strip).to eq(expected_yaml.strip)
  end

  it "deserializes from YAML with render_nil option" do
    yaml = <<~YAML
      ---
      glaze:
    YAML

    pottery = RenderNil.from_yaml(yaml)
    expect(pottery.name).to eq("Unnamed Pottery")
    expect(pottery.glaze).to be_nil
  end
end
