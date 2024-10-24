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

module XmlMapping
  class ChildNamespaceNil < Lutaml::Model::Serializable
    attribute :element_default_namespace, :string
    attribute :element_nil_namespace, :string
    attribute :element_new_namespace, :string

    xml do
      root "ChildNamespaceNil"
      namespace "http://www.omg.org/spec/XMI/20131001", "xmi"

      # this will inherit the namespace from the parent i.e <xmi:ElementDefaultNamespace>
      map_element "ElementDefaultNamespace", to: :element_default_namespace

      # this will have nil namesapce applied i.e <ElementNilNamespace>
      map_element "ElementNilNamespace", to: :element_nil_namespace,
                                         prefix: nil,
                                         namespace: nil

      # this will have new namespace i.e <new:ElementNewNamespace>
      map_element "ElementNewNamespace", to: :element_new_namespace,
                                         prefix: "new",
                                         namespace: "http://www.omg.org/spec/XMI/20161001"
    end
  end

  class Address < Lutaml::Model::Serializable
    attribute :street, ::Lutaml::Model::Type::String, raw: true
    attribute :city, :string, raw: true
    attribute :address, Address

    xml do
      root "address"

      map_element "street", to: :street
      map_element "city", to: :city
    end
  end

  class Person < Lutaml::Model::Serializable
    attribute :name, Lutaml::Model::Type::String
    attribute :address, XmlMapping::Address
  end

  class Mfenced < Lutaml::Model::Serializable
    attribute :open, :string

    xml do
      root "mfenced"
      map_attribute "open", to: :open
    end
  end

  class MmlMath < Lutaml::Model::Serializable
    attribute :mfenced, Mfenced

    xml do
      root "math"
      namespace "http://www.w3.org/1998/Math/MathML"
      map_element :mfenced, to: :mfenced
    end
  end

  class AttributeNamespace < Lutaml::Model::Serializable
    attribute :alpha, :string
    attribute :beta, :string

    xml do
      root "example"
      namespace "http://www.check.com", "ns1"

      map_attribute "alpha", to: :alpha,
                             namespace: "http://www.example.com",
                             prefix: "ex1"

      map_attribute "beta", to: :beta
    end
  end

  class SameNameDifferentNamespace < Lutaml::Model::Serializable
    attribute :gml_application_schema, :string
    attribute :citygml_application_schema, :string
    attribute :application_schema, :string
    attribute :app, :string

    xml do
      root "SameElementName"
      namespace "http://www.omg.org/spec/XMI/20131001", nil

      map_element "ApplicationSchema", to: :gml_application_schema,
                                       namespace: "http://www.sparxsystems.com/profiles/GML/1.0",
                                       prefix: "GML"

      map_element "ApplicationSchema", to: :citygml_application_schema,
                                       namespace: "http://www.sparxsystems.com/profiles/CityGML/1.0",
                                       prefix: "CityGML"

      map_element "ApplicationSchema", to: :application_schema

      map_attribute "App", to: :app
    end
  end

  class SchemaLocationOrdered < Lutaml::Model::Serializable
    attribute :content, :string
    attribute :second, SchemaLocationOrdered

    xml do
      root "schemaLocationOrdered", mixed: true

      map_content to: :content
      map_element "schemaLocationOrdered", to: :second
    end
  end
end

RSpec.describe Lutaml::Model::XmlMapping do
  let(:mapping) { described_class.new }

  context "attribute namespace" do
    input_xml = '<ns1:example ex1:alpha="hello" beta="bye" xmlns:ns1="http://www.check.com" xmlns:ex1="http://www.example.com"></ns1:example>'

    it "checks the attribute with and without namespace" do
      parsed = XmlMapping::AttributeNamespace.from_xml(input_xml)
      expect(parsed.alpha).to eq("hello")
      expect(parsed.beta).to eq("bye")
      expect(parsed.to_xml).to be_equivalent_to(input_xml)
    end
  end

  context "explicit namespace" do
    mml = '<math xmlns="http://www.w3.org/1998/Math/MathML"><mfenced open="("></mfenced></math>'

    it "nil namespace" do
      parsed = XmlMapping::MmlMath.from_xml(mml)
      expect(parsed.to_xml).to be_equivalent_to(mml)
    end
  end

  context "with same name elements" do
    let(:input_xml) do
      <<~XML
        <SameElementName App="hello" xmlns="http://www.omg.org/spec/XMI/20131001" xmlns:GML="http://www.sparxsystems.com/profiles/GML/1.0" xmlns:CityGML="http://www.sparxsystems.com/profiles/CityGML/1.0">
          <GML:ApplicationSchema>GML App</GML:ApplicationSchema>
          <CityGML:ApplicationSchema>CityGML App</CityGML:ApplicationSchema>
          <ApplicationSchema>App</ApplicationSchema>
        </SameElementName>
      XML
    end

    it "parses XML and serializes elements with the same name" do
      parsed = XmlMapping::SameNameDifferentNamespace.from_xml(input_xml)

      expect(parsed.citygml_application_schema).to eq("CityGML App")
      expect(parsed.gml_application_schema).to eq("GML App")
      expect(parsed.application_schema).to eq("App")
      expect(parsed.app).to eq("hello")
      expect(parsed.element_order).to eq(["text", "ApplicationSchema", "text", "ApplicationSchema", "text", "ApplicationSchema", "text"])
      expect(XmlMapping::SameNameDifferentNamespace.from_xml(input_xml).to_xml).to be_equivalent_to(input_xml)
    end
  end

  context "with elements have different prefixed namespaces" do
    before do
      mapping.root("XMI")
      mapping.namespace("http://www.omg.org/spec/XMI/20131001")
      mapping.map_element(
        "ApplicationSchema",
        to: :gml_application_schema,
        namespace: "http://www.sparxsystems.com/profiles/GML/1.0",
        prefix: "GML",
      )
      mapping.map_element(
        "ApplicationSchema",
        to: :citygml_application_schema,
        namespace: "http://www.sparxsystems.com/profiles/CityGML/1.0",
        prefix: "CityGML",
      )
      mapping.map_element(
        "ApplicationSchema",
        to: :citygml_application_schema,
        namespace: "http://www.sparxsystems.com/profiles/CGML/1.0",
        prefix: "CGML",
      )
    end

    it "maps elements correctly" do
      expect(mapping.elements[0].namespace).to eq("http://www.sparxsystems.com/profiles/GML/1.0")
      expect(mapping.elements[1].namespace).to eq("http://www.sparxsystems.com/profiles/CityGML/1.0")
      expect(mapping.elements[2].namespace).to eq("http://www.sparxsystems.com/profiles/CGML/1.0")
      expect(mapping.elements.size).to eq(3)
    end
  end

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

  context "with nil element-level namespace" do
    let(:expected_xml) do
      <<~XML
        <xmi:ChildNamespaceNil xmlns:xmi="http://www.omg.org/spec/XMI/20131001" xmlns:new="http://www.omg.org/spec/XMI/20161001">
          <xmi:ElementDefaultNamespace>Default namespace</xmi:ElementDefaultNamespace>
          <ElementNilNamespace>No namespace</ElementNilNamespace>
          <new:ElementNewNamespace>New namespace</new:ElementNewNamespace>
        </xmi:ChildNamespaceNil>
      XML
    end

    let(:model) do
      XmlMapping::ChildNamespaceNil.new(
        {
          element_default_namespace: "Default namespace",
          element_nil_namespace: "No namespace",
          element_new_namespace: "New namespace",
        },
      )
    end

    it "expect to apply correct namespaces" do
      expect(model.to_xml).to be_equivalent_to(expected_xml)
    end
  end

  context "with schemaLocation" do
    context "when mixed: false" do
      let(:xml) do
        <<~XML
          <p xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.opengis.net/gml/3.2 http://schemas.opengis.net/gml/3.2.1/gml.xsd">
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

    context "when mixed: true" do
      let(:xml) do
        <<~XML
          <schemaLocationOrdered xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.opengis.net/gml/3.2 http://schemas.opengis.net/gml/3.2.1/gml.xsd">
            <schemaLocationOrdered xmlns:xsi="http://another-instance"
               xsi:schemaLocation="http://www.opengis.net/gml/3.7">
              Some text inside paragraph
            </schemaLocationOrdered>
          </schemaLocationOrdered>
        XML
      end

      it "contain schemaLocation attributes" do
        expect(XmlMapping::SchemaLocationOrdered.from_xml(xml).to_xml).to be_equivalent_to(xml)
      end
    end
  end

  context "with multiple schemaLocations" do
    let(:xml) do
      <<~XML
        <p xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
           xsi:schemaLocation="http://www.opengis.net/gml/3.2 http://schemas.opengis.net/gml/3.2.1/gml.xsd http://www.w3.org/1999/xlink http://www.w3.org/1999/xlink.xsd">
          <p xmlns:xsi="http://another-instance"
             xsi:schemaLocation="http://www.opengis.net/gml/3.7 http://schemas.opengis.net/gml/3.7.1/gml.xsd http://www.isotc211.org/2005/gmd http://schemas.opengis.net/iso/19139/20070417/gmd/gmd.xsd">
            Some text inside paragraph
          </p>
        </p>
      XML
    end

    it "parses and serializes multiple schemaLocation attributes" do
      parsed = Paragraph.from_xml(xml)
      expect(parsed.schema_location.size).to eq(2)
      expect(parsed.schema_location[0].namespace).to eq("http://www.opengis.net/gml/3.2")
      expect(parsed.schema_location[0].location).to eq("http://schemas.opengis.net/gml/3.2.1/gml.xsd")
      expect(parsed.schema_location[1].namespace).to eq("http://www.w3.org/1999/xlink")
      expect(parsed.schema_location[1].location).to eq("http://www.w3.org/1999/xlink.xsd")

      serialized = parsed.to_xml
      expect(serialized).to be_equivalent_to(xml)
      expect(serialized).to include('xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
      expect(serialized).to include('xsi:schemaLocation="http://www.opengis.net/gml/3.2 http://schemas.opengis.net/gml/3.2.1/gml.xsd http://www.w3.org/1999/xlink http://www.w3.org/1999/xlink.xsd"')
    end

    it "handles nested elements with different schemaLocations" do
      parsed = Paragraph.from_xml(xml)
      nested_p = parsed.paragraph

      expect(nested_p).to be_a(Paragraph)
      expect(nested_p.schema_location.size).to eq(2)
      expect(nested_p.schema_location[0].namespace).to eq("http://www.opengis.net/gml/3.7")
      expect(nested_p.schema_location[0].location).to eq("http://schemas.opengis.net/gml/3.7.1/gml.xsd")
      expect(nested_p.schema_location[1].namespace).to eq("http://www.isotc211.org/2005/gmd")
      expect(nested_p.schema_location[1].location).to eq("http://schemas.opengis.net/iso/19139/20070417/gmd/gmd.xsd")

      serialized = parsed.to_xml
      expect(serialized).to include('xmlns:xsi="http://another-instance"')
      expect(serialized).to include('xsi:schemaLocation="http://www.opengis.net/gml/3.7 http://schemas.opengis.net/gml/3.7.1/gml.xsd http://www.isotc211.org/2005/gmd http://schemas.opengis.net/iso/19139/20070417/gmd/gmd.xsd"')
    end

    it "creates XML with multiple schemaLocations" do
      paragraph = Paragraph.new(
        schema_location: Lutaml::Model::SchemaLocation.new(
          schema_location: {
            "http://www.opengis.net/gml/3.2" => "http://schemas.opengis.net/gml/3.2.1/gml.xsd",
            "http://www.w3.org/1999/xlink" => "http://www.w3.org/1999/xlink.xsd",
          },
          prefix: "xsi",
        ),
        paragraph: Paragraph.new(
          schema_location: Lutaml::Model::SchemaLocation.new(
            schema_location: {
              "http://www.opengis.net/gml/3.7" => "http://schemas.opengis.net/gml/3.7.1/gml.xsd",
              "http://www.isotc211.org/2005/gmd" => "http://schemas.opengis.net/iso/19139/20070417/gmd/gmd.xsd",
            },
            prefix: "xsi",
            namespace: "http://another-instance",
          ),
          text: ["Some text inside paragraph"],
        ),
      )

      serialized = paragraph.to_xml
      expect(serialized).to be_equivalent_to(xml)
    end
  end

  context "with raw mapping" do
    let(:input_xml) do
      <<~XML
        <person>
          <name>John Doe</name>
          <address>
            <street>
              <a>N</a>
              <p>adf</p>
            </street>
            <city><a>M</a></city>
          </address>
        </person>
      XML
    end

    let(:expected_street) do
      if Lutaml::Model::Config.xml_adapter == Lutaml::Model::XmlAdapter::OxAdapter
        "<a>N</a>\n<p>adf</p>\n"
      else
        "\n      <a>N</a>\n      <p>adf</p>\n    "
      end
    end

    let(:model) { XmlMapping::Person.from_xml(input_xml) }

    it "expect to contain raw xml" do
      expect(model.address.street).to eq(expected_street)
      expect(model.address.city.strip).to eq("<a>M</a>")
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
