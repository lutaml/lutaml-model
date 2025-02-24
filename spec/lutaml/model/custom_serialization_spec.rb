require "spec_helper"
require "lutaml/model"

class CustomSerialization < Lutaml::Model::Serializable
  attribute :full_name, :string
  attribute :size, :integer
  attribute :color, :string
  attribute :description, :string
  attribute :country, :string

  json do
    map "name", to: :full_name, with: { to: :name_to_json }
    map "color", to: :color, with: { from: :color_from_json }
    map "size", with: { to: :size_to_json, from: :size_from_json }
    map "description",
        with: { to: :description_to_json, from: :description_from_json }
    map "country",
        with: { to: :country_to_json, from: :country_from_json }
  end

  xml do
    root "CustomSerialization"

    # name, color are used to test XML elements with custom methods
    map_element "Name", to: :full_name, with: { from: :name_from_xml }
    map_element "Color", with: { to: :color_to_xml, from: :color_from_xml }

    # size is used to test XML attribute with custom methods
    map_attribute "Size", with: { to: :size_to_xml, from: :size_from_xml }
    map_attribute "Country", to: :country, with: { to: :country_to_xml }

    # description is used to test XML textual content
    map_content to: :description, with: { from: :description_from_xml }
  end

  def name_to_json(model, doc)
    doc["name"] = "JSON Masterpiece: #{model.full_name}"
  end

  def size_to_json(model, doc)
    doc["size"] = model.size + 3
  end

  def size_from_json(model, value)
    model.size = value - 3
  end

  def color_from_json(model, value)
    model.color = value.downcase
  end

  def description_to_json(model, doc)
    doc["description"] = "JSON Description: #{model.description}"
  end

  def description_from_json(model, value)
    model.description = value.sub(/^JSON Description: /, "")
  end

  def country_to_json(model, doc)
    doc["country"] = model.country.downcase
  end

  def country_from_json(model, value)
    model.country = value
  end

  def name_from_xml(model, values)
    model.full_name = values.text.sub(/^XML Masterpiece: /, "")
  end

  def size_to_xml(model, parent, doc)
    doc.add_attribute(parent, "Size", model.size + 3)
  end

  def size_from_xml(model, value)
    model.size = value.to_i - 3
  end

  def country_to_xml(model, parent, doc)
    doc.add_attribute(parent, "Country", model.country.upcase)
  end

  def color_to_xml(model, parent, doc)
    color_element = doc.create_element("Color")
    doc.add_text(color_element, model.color.upcase)
    doc.add_element(parent, color_element)
  end

  def color_from_xml(model, values)
    model.color = values.first.text.downcase
  end

  def description_from_xml(model, value)
    model.description = value.join.strip.sub(/^XML Description: /, "")
  end
end

class GrammarInfo < Lutaml::Model::Serializable
  attribute :part_of_speech, :string, values: %w[user admin super_admin]

  key_value do
    map :part_of_speech, with: { to: :part_of_speech_to_key_value, from: :part_of_speech_from_key_value }
  end

  xml do
    root "GrammarInfo"
    map_element :part_of_speech, with: { to: :part_of_speech_to_xml, from: :part_of_speech_from_xml }
  end

  def part_of_speech_from_key_value(model, value)
    model.part_of_speech = value
  end

  def part_of_speech_to_key_value(model, doc)
    doc["part_of_speech"] = model.part_of_speech
  end

  def part_of_speech_from_xml(model, nodes)
    model.part_of_speech = nodes.first.text
  end

  def part_of_speech_to_xml(model, parent, doc)
    el = doc.create_element("part_of_speech")
    doc.add_text(el, model.part_of_speech)
    doc.add_element(parent, el)
  end
end

class Document < Lutaml::Model::Serializable
  attribute :content, :string

  xml do
    root "document"
    map_all to: :content, with: { from: :content_from_xml }
  end

  def content_from_xml(model, value)
    model.content = value.strip
  end
end

RSpec.describe CustomSerialization do
  let(:attributes) do
    {
      full_name: "Vase",
      size: 12,
      color: "blue",
      description: "A beautiful ceramic vase",
      country: "spain",
    }
  end
  let(:model) { described_class.new(attributes) }

  context "with JSON serialization" do
    it "serializes to JSON with custom methods" do
      expected_json = {
        name: "JSON Masterpiece: Vase",
        color: "blue",
        size: 15,
        description: "JSON Description: A beautiful ceramic vase",
        country: "spain",
      }.to_json

      expect(model.to_json).to eq(expected_json)
    end

    it "deserializes from JSON with custom methods" do
      json = {
        name: "Vase",
        color: "BLUE",
        size: 15,
        description: "JSON Description: A beautiful ceramic vase",
        country: "spain",
      }.to_json

      ceramic = described_class.from_json(json)

      expect(ceramic.full_name).to eq(model.full_name)
      expect(ceramic.size).to eq(model.size)
      expect(ceramic.color).to eq(model.color)
      expect(ceramic.description).to eq(model.description)
      expect(ceramic.country).to eq(model.country)
    end
  end

  context "with partial JSON input" do
    it "deserializes from JSON with missing attributes" do
      json = {
        name: "Vase",
        color: "BLUE",
      }.to_json

      ceramic = described_class.from_json(json)

      expect(ceramic.full_name).to eq("Vase")
      expect(ceramic.color).to eq("blue")
      expect(ceramic.size).to be_nil
      expect(ceramic.description).to be_nil
      expect(ceramic.country).to be_nil
    end
  end

  context "with XML serialization" do
    it "serializes to XML with custom methods" do
      expected_xml = <<~XML
        <CustomSerialization Size="15" Country="SPAIN">
          <Name>Vase</Name>
          <Color>BLUE</Color>
          A beautiful ceramic vase
        </CustomSerialization>
      XML

      expect(model.to_xml).to be_equivalent_to(expected_xml)
    end

    it "deserializes from XML with custom methods" do
      xml = <<~XML
        <CustomSerialization Size="15" Country="SPAIN">
          <Name>XML Masterpiece: Vase</Name>
          <Color>BLUE</Color>
          XML Description: A beautiful ceramic vase
        </CustomSerialization>
      XML

      ceramic = described_class.from_xml(xml)
      expect(ceramic.full_name).to eq(model.full_name)
      expect(ceramic.size).to eq(model.size)
      expect(ceramic.color).to eq(model.color)
      expect(ceramic.description).to eq(model.description)
    end

    it "serialize and deserialize map_all with custom methods" do
      xml = <<~XML
        <document>
          <content>
            <Name>XML Masterpiece: Vase</Name>
            <Color>BLUE</Color>
          </content>
        </document>
      XML

      document = Document.from_xml(xml)

      expect(document.content).to eq("<content>\n    <Name>XML Masterpiece: Vase</Name>\n    <Color>BLUE</Color>\n  </content>")
      expect(document.to_xml).to be_equivalent_to(xml)
    end
  end

  context "when enum used with custom methods" do
    let(:hash) do
      {
        "part_of_speech" => "user",
      }
    end

    it "correctly persist value for yaml" do
      instance = GrammarInfo.from_yaml(hash.to_yaml)
      serialized = instance.to_yaml

      expect(instance.part_of_speech).to eq("user")
      expect(serialized).to eq(hash.to_yaml)
    end

    it "correctly persist value for json" do
      instance = GrammarInfo.from_json(hash.to_json)
      serialized = instance.to_json

      expect(instance.part_of_speech).to eq("user")
      expect(serialized).to eq(hash.to_json)
    end

    it "correctly handles value for xml" do
      xml_input = <<~XML
        <GrammarInfo>
          <part_of_speech>user</part_of_speech>
        </GrammarInfo>
      XML

      instance = GrammarInfo.from_xml(xml_input)
      expect(instance.part_of_speech).to eq("user")
      expect(instance.user?).to be true
      expect(instance.admin?).to be false
      expect(instance.super_admin?).to be false

      serialized = instance.to_xml
      expect(serialized).to be_equivalent_to(xml_input)
    end
  end
end
