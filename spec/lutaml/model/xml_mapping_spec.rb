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
  attribute :paragraph, Paragraph

  xml do
    root "p"

    map_content to: :text
    map_element "p", to: :paragraph
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

  context "with schemaLocation" do
    let(:xml) do
      <<~XML
        <p xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
           xsi:schemaLocation="http://www.opengis.net/gml/3.2
                               http://schemas.opengis.net/gml/3.2.1/gml.xsd">
          <p xmlns:xsi="http://another-instance"
             xsi:schemaLocation="http://www.opengis.net/gml/3.7">
            Some text inside paragraph
          </p>
        </p>
      XML
    end

    it "contain schemaLocation attributes" do
      expect(Paragraph.from_xml(xml).to_xml).to be_equivalent_to(xml)
    end
  end

  xcontext "with multiple schemaLocations" do
    let(:xml) do
      <<~XML
        <p xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
           xsi:schemaLocation="http://www.opengis.net/gml/3.2 http://schemas.opengis.net/gml/3.2.1/gml.xsd
                               http://www.w3.org/1999/xlink http://www.w3.org/1999/xlink.xsd">
          <p xmlns:xsi="http://another-instance"
             xsi:schemaLocation="http://www.opengis.net/gml/3.7 http://schemas.opengis.net/gml/3.7.1/gml.xsd
                                 http://www.isotc211.org/2005/gmd http://schemas.opengis.net/iso/19139/20070417/gmd/gmd.xsd">
            Some text inside paragraph
          </p>
        </p>
      XML
    end

    it "parses and serializes multiple schemaLocation attributes" do
      parsed = Paragraph.from_xml(xml)
      expect(parsed.schema_locations).to be_an(Array)
      expect(parsed.schema_locations.size).to eq(2)
      expect(parsed.schema_locations[0].namespace).to eq("http://www.opengis.net/gml/3.2")
      expect(parsed.schema_locations[0].location).to eq("http://schemas.opengis.net/gml/3.2.1/gml.xsd")
      expect(parsed.schema_locations[1].namespace).to eq("http://www.w3.org/1999/xlink")
      expect(parsed.schema_locations[1].location).to eq("http://www.w3.org/1999/xlink.xsd")

      serialized = parsed.to_xml
      expect(serialized).to be_equivalent_to(xml)
      expect(serialized).to include('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
      expect(serialized).to include('xsi:schemaLocation="http://www.opengis.net/gml/3.2 http://schemas.opengis.net/gml/3.2.1/gml.xsd http://www.w3.org/1999/xlink http://www.w3.org/1999/xlink.xsd"')
    end

    it "handles nested elements with different schemaLocations" do
      parsed = Paragraph.from_xml(xml)
      nested_p = parsed.text.first

      expect(nested_p).to be_a(Paragraph)
      expect(nested_p.schema_locations).to be_an(Array)
      expect(nested_p.schema_locations.size).to eq(2)
      expect(nested_p.schema_locations[0].namespace).to eq("http://www.opengis.net/gml/3.7")
      expect(nested_p.schema_locations[0].location).to eq("http://schemas.opengis.net/gml/3.7.1/gml.xsd")
      expect(nested_p.schema_locations[1].namespace).to eq("http://www.isotc211.org/2005/gmd")
      expect(nested_p.schema_locations[1].location).to eq("http://schemas.opengis.net/iso/19139/20070417/gmd/gmd.xsd")

      serialized = parsed.to_xml
      expect(serialized).to include('xmlns:xsi="http://another-instance"')
      expect(serialized).to include('xsi:schemaLocation="http://www.opengis.net/gml/3.7 http://schemas.opengis.net/gml/3.7.1/gml.xsd http://www.isotc211.org/2005/gmd http://schemas.opengis.net/iso/19139/20070417/gmd/gmd.xsd"')
    end

    it "creates XML with multiple schemaLocations" do
      paragraph = Paragraph.new(
        schema_locations: [
          Lutaml::Model::SchemaLocation.new("http://www.opengis.net/gml/3.2", "http://schemas.opengis.net/gml/3.2.1/gml.xsd"),
          Lutaml::Model::SchemaLocation.new("http://www.w3.org/1999/xlink", "http://www.w3.org/1999/xlink.xsd"),
        ],
        text: [
          Paragraph.new(
            schema_locations: [
              Lutaml::Model::SchemaLocation.new("http://www.opengis.net/gml/3.7", "http://schemas.opengis.net/gml/3.7.1/gml.xsd"),
              Lutaml::Model::SchemaLocation.new("http://www.isotc211.org/2005/gmd", "http://schemas.opengis.net/iso/19139/20070417/gmd/gmd.xsd"),
            ],
            xsi_namespace: "http://another-instance",
            text: ["Some text inside paragraph"],
          ),
        ],
      )

      serialized = paragraph.to_xml
      expect(serialized).to be_equivalent_to(xml)
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
