require "spec_helper"
require "lutaml/model"

class CustomSerialization < Lutaml::Model::Serializable
  attribute :name, :string
  attribute :size, :integer
  attribute :color, :string
  attribute :description, :string

  json do
    map "name", to: :name, with: { to: :name_to_json, from: :name_from_json }
    map "size", to: :size
    map "color", to: :color,
                 with: { to: :color_to_json, from: :color_from_json }
    map "description", to: :description,
                       with: { to: :description_to_json, from: :description_from_json }
  end

  xml do
    root "CustomSerialization"
    map_element "Name", to: :name,
                        with: { to: :name_to_xml, from: :name_from_xml }
    map_attribute "Size", to: :size
    map_element "Color", to: :color,
                         with: { to: :color_to_xml, from: :color_from_xml }
    map_content to: :description,
                with: { to: :description_to_xml,
                        from: :description_from_xml }
  end

  def name_to_json(_model, value)
    "JSON Masterpiece: #{value}"
  end

  def name_from_json(_model, doc)
    doc["name"].sub(/^JSON Masterpiece: /, "")
  end

  def color_to_json(_model, value)
    value.upcase
  end

  def color_from_json(_model, doc)
    doc["color"].downcase
  end

  def description_to_json(_model, value)
    "JSON Description: #{value}"
  end

  def description_from_json(_model, doc)
    doc["description"].sub(/^JSON Description: /, "")
  end

  def name_to_xml(_model, value)
    "XML Masterpiece: #{value}"
  end

  def name_from_xml(_model, value)
    value.sub(/^XML Masterpiece: /, "")
  end

  def color_to_xml(_model, value)
    value.upcase
  end

  def color_from_xml(_model, value)
    value.downcase
  end

  def description_to_xml(_model, value)
    "XML Description: #{value}"
  end

  def description_from_xml(_model, value)
    value.sub(/^XML Description: /, "")
  end
end

RSpec.describe CustomSerialization do
  let(:attributes) do
    {
      name: "Vase",
      size: 12,
      color: "blue",
      description: "A beautiful ceramic vase",
    }
  end
  let(:model) { described_class.new(attributes) }

  context "with JSON serialization" do
    it "serializes to JSON with custom methods" do
      expected_json = {
        name: "JSON Masterpiece: Vase",
        size: 12,
        color: "BLUE",
        description: "JSON Description: A beautiful ceramic vase",
      }.to_json

      expect(model.to_json).to eq(expected_json)
    end

    it "deserializes from JSON with custom methods" do
      json = {
        name: "JSON Masterpiece: Vase",
        size: 12,
        color: "BLUE",
        description: "JSON Description: A beautiful ceramic vase",
      }.to_json

      ceramic = described_class.from_json(json)
      expect(ceramic.name).to eq("Vase")
      expect(ceramic.size).to eq(12)
      expect(ceramic.color).to eq("blue")
      expect(ceramic.description).to eq("A beautiful ceramic vase")
    end
  end

  context "with XML serialization" do
    it "serializes to XML with custom methods" do
      expected_xml = <<~XML
        <CustomSerialization Size="12">
          <Name>XML Masterpiece: Vase</Name>
          <Color>BLUE</Color>
          XML Description: A beautiful ceramic vase
        </CustomSerialization>
      XML

      expect(model.to_xml).to be_equivalent_to(expected_xml)
    end

    it "deserializes from XML with custom methods" do
      xml = <<~XML
        <CustomSerialization Size="12">
          <Name>XML Masterpiece: Vase</Name>
          <Color>BLUE</Color>
          XML Description: A beautiful ceramic vase
        </CustomSerialization>
      XML

      ceramic = described_class.from_xml(xml)
      expect(ceramic.name).to eq("Vase")
      expect(ceramic.size).to eq(12)
      expect(ceramic.color).to eq("blue")
      expect(ceramic.description).to eq("A beautiful ceramic vase")
    end
  end
end
