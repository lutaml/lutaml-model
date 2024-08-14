require "spec_helper"
require_relative "../../../lib/lutaml/model/xml_mapping"
require_relative "../../../lib/lutaml/model/xml_mapping_rule"

# Define a sample class for testing map_content
class Italic < Lutaml::Model::Serializable
  attribute :text, Lutaml::Model::Type::String, collection: true

  xml do
    root "i"
    map_content to: :text
  end
end

# Define a sample class for testing p tag
class Paragraph < Lutaml::Model::Serializable
  attribute :text, Lutaml::Model::Type::String

  xml do
    root "p"

    map_content to: :text
  end
end

RSpec.describe Lutaml::Model::XmlMapping do
  let(:mapping) { described_class.new }

  context "with default namespace" do
    before do
      mapping.root("ceramic")
      mapping.namespace("https://example.com/ceramic/1.2")
      mapping.map_element("type", to: :type)
      mapping.map_element("color", to: :color, delegate: :glaze)
      mapping.map_element("finish", to: :finish, delegate: :glaze)
    end

    it "sets the default namespace for the root element" do
      expect(mapping.namespace_uri).to eq("https://example.com/ceramic/1.2")
      expect(mapping.namespace_prefix).to be_nil
    end

    it "maps elements correctly" do
      expect(mapping.elements.size).to eq(3)
      expect(mapping.elements[0].name).to eq("type")
      expect(mapping.elements[1].delegate).to eq(:glaze)
    end
  end

  context "with prefixed namespace" do
    before do
      mapping.root("ceramic")
      mapping.namespace("https://example.com/ceramic/1.2", "cera")
      mapping.map_element("type", to: :type)
      mapping.map_element("color", to: :color, delegate: :glaze)
      mapping.map_element("finish", to: :finish, delegate: :glaze)
    end

    it "sets the namespace with prefix for the root element" do
      expect(mapping.namespace_uri).to eq("https://example.com/ceramic/1.2")
      expect(mapping.namespace_prefix).to eq("cera")
    end

    it "maps elements correctly" do
      expect(mapping.elements.size).to eq(3)
      expect(mapping.elements[0].name).to eq("type")
      expect(mapping.elements[1].delegate).to eq(:glaze)
    end
  end

  context "with element-level namespace" do
    before do
      mapping.root("ceramic")
      mapping.map_element(
        "type",
        to: :type,
        namespace: "https://example.com/ceramic/1.2",
        prefix: "cera",
      )
      mapping.map_element("color", to: :color, delegate: :glaze)
      mapping.map_element("finish", to: :finish, delegate: :glaze)
    end

    it "sets the namespace for individual elements" do
      expect(mapping.elements.size).to eq(3)
      expect(mapping.elements[0].namespace).to eq("https://example.com/ceramic/1.2")
      expect(mapping.elements[0].prefix).to eq("cera")
      expect(mapping.elements[1].delegate).to eq(:glaze)
    end
  end

  context "with attribute-level namespace" do
    before do
      mapping.root("ceramic")
      mapping.map_attribute(
        "date",
        to: :date,
        namespace: "https://example.com/ceramic/1.2",
        prefix: "cera",
      )
      mapping.map_element("type", to: :type)
      mapping.map_element("color", to: :color, delegate: :glaze)
      mapping.map_element("finish", to: :finish, delegate: :glaze)
    end

    it "sets the namespace for individual attributes" do
      expect(mapping.attributes.size).to eq(1)
      expect(mapping.attributes[0].namespace).to eq("https://example.com/ceramic/1.2")
      expect(mapping.attributes[0].prefix).to eq("cera")
    end
  end

  context "with content mapping" do
    let(:xml_data) { "<i>my text <b>bold</b> is in italics</i>" }
    let(:italic) { Italic.from_xml(xml_data) }

    it "parses the textual content of an XML element" do
      expect(italic.text).to eq(["my text ", " is in italics"])
    end
  end

  context "with p object" do
    describe "convert from xml containing p tag" do
      let(:xml_data) { "<p>my text for paragraph</p>" }
      let(:paragraph) { Paragraph.from_xml(xml_data) }

      it "parses the textual content of an XML element" do
        expect(paragraph.text).to eq("my text for paragraph")
      end
    end

    describe "generate xml with p tag" do
      let(:paragraph) { Paragraph.new(text: "my text for paragraph") }
      let(:expected_xml) { "<p>my text for paragraph</p>" }

      it "converts to xml correctly" do
        expect(paragraph.to_xml).to eq(expected_xml)
      end
    end
  end
end
