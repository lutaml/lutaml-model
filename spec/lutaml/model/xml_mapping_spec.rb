require "spec_helper"

require "lutaml/model/xml/ox_adapter"
require "lutaml/model/xml/oga_adapter"
require_relative "../../support/xml_mapping_namespaces"

# Define a sample class for testing map content
class Italic < Lutaml::Model::Serializable
  attribute :text, Lutaml::Model::Type::String, collection: true

  xml do
    element "i"
    map_content to: :text
  end
end

# Define a sample class for testing p tag
class Paragraph < Lutaml::Model::Serializable
  attribute :text, Lutaml::Model::Type::String
  attribute :paragraph, Paragraph

  xml do
    element "p"

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
      element "ChildNamespaceNil"
      namespace XmiNamespace

      # this will inherit the namespace from the parent i.e <xmi:ElementDefaultNamespace>
      map_element "ElementDefaultNamespace", to: :element_default_namespace

      # this will have nil namesapce applied i.e <ElementNilNamespace>
      map_element "ElementNilNamespace", to: :element_nil_namespace,
                                         namespace: nil

      # this will have new namespace i.e <new:ElementNewNamespace>
      map_element "ElementNewNamespace", to: :element_new_namespace,
                                         namespace: XmiNewNamespace
    end
  end

  class Address < Lutaml::Model::Serializable
    attribute :street, ::Lutaml::Model::Type::String, raw: true
    attribute :city, :string, raw: true
    attribute :text, :string
    attribute :address, Address

    xml do
      element "address"

      map_element "street", to: :street
      map_element "city", to: :city
      map_element "text", to: :text
    end
  end

  class Person < Lutaml::Model::Serializable
    attribute :name, Lutaml::Model::Type::String
    attribute :address, XmlMapping::Address
  end

  class Mfenced < Lutaml::Model::Serializable
    attribute :open, :string

    xml do
      element "mfenced"
      map_attribute "open", to: :open
    end
  end

  class MmlMath < Lutaml::Model::Serializable
    attribute :mfenced, Mfenced

    xml do
      element "math"
      namespace MathMlNamespace
      map_element :mfenced, to: :mfenced
    end
  end

  class AttributeNamespace < Lutaml::Model::Serializable
    attribute :alpha, :string
    attribute :beta, :string

    xml do
      element "example"
      namespace CheckNamespace

      map_attribute "alpha", to: :alpha,
                             namespace: ExampleNamespace

      map_attribute "beta", to: :beta
    end
  end

  class SameNameDifferentNamespace < Lutaml::Model::Serializable
    attribute :gml_application_schema, :string
    attribute :citygml_application_schema, :string
    attribute :application_schema, :string
    attribute :app, :string

    xml do
      element "SameElementName"
      namespace XmiNamespace

      map_element "ApplicationSchema", to: :gml_application_schema,
                                       namespace: GmlNamespace

      map_element "ApplicationSchema", to: :citygml_application_schema,
                                       namespace: CityGmlNamespace

      map_element "ApplicationSchema", to: :application_schema

      map_attribute "App", to: :app
    end
  end

  class AnnotatedElement < Lutaml::Model::Serializable
    attribute :idref, :string

    xml do
      element "annotatedElement"
      map_attribute "idref", to: :idref,
                             namespace: XmiNamespace
    end
  end

  class OwnedComment < Lutaml::Model::Serializable
    attribute :annotated_attribute, :string
    attribute :annotated_element, AnnotatedElement

    xml do
      element "ownedComment"
      map_attribute "annotatedElement", to: :annotated_attribute
      map_element "annotatedElement", to: :annotated_element,
                                      namespace: nil
    end
  end

  class Date < Lutaml::Model::Serializable
    attribute :type, :string
    attribute :text, :string
    attribute :content, :string
    attribute :from, :string
    attribute :to, :string
    attribute :on, :string

    xml do
      root "date", mixed: true
      map_attribute "type", to: :type
      map_attribute "text", to: :text
      map_content to: :content
      map_element "from", to: :from
      map_element "to", to: :to
      map_element "on", to: :on
    end
  end

  class OverrideDefaultNamespacePrefix < Lutaml::Model::Serializable
    attribute :same_element_name, SameNameDifferentNamespace

    xml do
      element "OverrideDefaultNamespacePrefix"
      map_element :SameElementName, to: :same_element_name,
                                    namespace: XmiNamespace
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

  class ToBeDuplicated < Lutaml::Model::Serializable
    attribute :content, :string
    attribute :element, :string
    attribute :attribute, :string

    xml do
      element "ToBeDuplicated"
      namespace TestingDuplicateNamespace

      map_content to: :content
      map_attribute "attribute", to: :attribute
      map_element "element", to: :element,
                             namespace: TestElementNamespace
    end
  end

  class SpecialCharContentWithMapAll < Lutaml::Model::Serializable
    attribute :all_content, :string

    xml do
      element "SpecialCharContentWithMapAll"

      map_all to: :all_content
    end
  end

  class MapAllWithCustomMethod < Lutaml::Model::Serializable
    attribute :all_content, :string

    xml do
      element "MapAllWithCustomMethod"

      map_all_content to: :all_content,
                      with: { to: :content_to_xml, from: :content_from_xml }
    end

    def content_to_xml(model, parent, doc)
      content = model.all_content.sub(/^<div>/, "").sub(/<\/div>$/, "")
      doc.add_xml_fragment(parent, content)
    end

    def content_from_xml(model, value)
      model.all_content = "<div>#{value}</div>"
    end
  end

  class WithMapAll < Lutaml::Model::Serializable
    attribute :all_content, :string
    attribute :attr, :string

    xml do
      element "WithMapAll"

      map_all to: :all_content
    end
  end

  class WithoutMapAll < Lutaml::Model::Serializable
    attribute :content, :string

    xml do
      element "WithoutMapAll"

      map_content to: :content
    end
  end

  class WithNestedMapAll < Lutaml::Model::Serializable
    attribute :age, :integer
    attribute :name, :string
    attribute :description, WithMapAll

    xml do
      element "WithNestedMapAll"

      map_attribute :age, to: :age
      map_element :name, to: :name
      map_element :description, to: :description
    end
  end

  class WithChildExplicitNamespace < Lutaml::Model::Serializable
    attribute :with_default_namespace, :string
    attribute :with_namespace, :string
    attribute :without_namespace, :string

    xml do
      element "WithChildExplicitNamespaceNil"
      namespace ParentNamespace

      map_element "DefaultNamespace", to: :with_default_namespace

      map_element "WithNamespace", to: :with_namespace,
                                   namespace: ChildNamespace

      map_element "WithoutNamespace", to: :without_namespace,
                                      namespace: nil
    end
  end

  class Documentation < Lutaml::Model::Serializable
    attribute :content, :string

    xml do
      root "documentation", mixed: true
      namespace XsdNamespace

      map_content to: :content
    end
  end

  class Schema < Lutaml::Model::Serializable
    attribute :documentation, Documentation, collection: true

    xml do
      element "schema"
      namespace XsdNamespace

      map_element :documentation, to: :documentation,
                                  namespace: XsdNamespace
    end
  end

  class TitleCollection < Lutaml::Model::Collection
    instances :items, :string

    xml do
      element "titles"
      map_attribute "title", to: :items, as_list: {
        import: ->(str) { str.split("; ") },
        export: ->(arr) { arr.join("; ") },
      }
    end
  end

  class TitleDelimiterCollection < Lutaml::Model::Collection
    instances :items, :string

    xml do
      element "titles"
      map_attribute "title", to: :items, delimiter: "; "
    end
  end
end

RSpec.describe Lutaml::Model::Xml::Mapping do
  describe "as_list feature for XML attributes" do
    let(:xml) { '<titles title="Title One; Title Two; Title Three"/>' }

    it "imports delimited attribute to array" do
      collection = XmlMapping::TitleCollection.from_xml(xml)
      expect(collection.items).to eq(["Title One", "Title Two", "Title Three"])
    end

    it "round-trips correctly" do
      collection = XmlMapping::TitleCollection.from_xml(xml)
      generated_xml = collection.to_xml
      expect(generated_xml).to be_xml_equivalent_to(xml)
    end
  end

  describe "delimiter feature for XML attributes" do
    let(:xml) { '<titles title="Title One; Title Two; Title Three"/>' }

    it "imports delimited attribute to array" do
      collection = XmlMapping::TitleDelimiterCollection.from_xml(xml)
      expect(collection.items).to eq(["Title One", "Title Two", "Title Three"])
    end

    it "round-trips delimited attribute correctly" do
      collection = XmlMapping::TitleDelimiterCollection.from_xml(xml)
      generated_xml = collection.to_xml
      expect(generated_xml).to be_xml_equivalent_to(xml)
    end
  end

  describe "find_by_to! error handling" do
    it "raises NoMappingFoundError when mapping is missing in xml mapping" do
      mapping = described_class.new
      expect do
        mapping.find_by_to!("nonexistent")
      end.to raise_error(Lutaml::Model::NoMappingFoundError,
                         /No mapping available for `nonexistent`/)
    end
  end

  shared_examples "having XML Mappings" do |adapter_class|
    around do |example|
      old_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_class

      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = old_adapter
    end

    # rubocop:disable all
    let(:mapping) { Lutaml::Model::Xml::Mapping.new }
    # rubocop:enable all

    context "with attribute having namespace" do
      let(:input_xml) do
        <<~XML
          <example xmlns="http://www.check.com"
                   ex1:alpha="hello"
                   beta="bye"
                   xmlns:ex1="http://www.example.com">
          </example>
        XML
      end

      it "checks the attribute with and without namespace" do
        parsed = XmlMapping::AttributeNamespace.from_xml(input_xml)

        expect(parsed.alpha).to eq("hello")
        expect(parsed.beta).to eq("bye")
        expect(parsed.to_xml).to be_xml_equivalent_to(input_xml)
      end
    end

    context "with explicit namespace" do
      let(:mml) do
        <<~XML
          <math xmlns="http://www.w3.org/1998/Math/MathML">
            <mfenced open="("></mfenced>
          </math>
        XML
      end

      let(:mml_nokogiri) do
        <<~XML
          <math xmlns="http://www.w3.org/1998/Math/MathML">
            <mfenced xmlns="" open="("></mfenced>
          </math>
        XML
      end

      it "nil namespace" do
        parsed = XmlMapping::MmlMath.from_xml(mml)
        # Nokogiri adds xmlns="" to prevent namespace inheritance (W3C compliant)
        # Ox and Oga don't add it (adapter-specific behavior)
        expected_xml = adapter_class == Lutaml::Model::Xml::NokogiriAdapter ? mml_nokogiri : mml
        expect(parsed.to_xml).to be_xml_equivalent_to(expected_xml)
      end
    end

    # Skipping for OX because it does not handle namespaces
    context "when overriding child namespace prefix",
            skip: adapter_class == Lutaml::Model::Xml::OxAdapter do
      let(:input_xml) do
        <<~XML
          <OverrideDefaultNamespacePrefix>
            <SameElementName xmlns="http://www.omg.org/spec/XMI/20131001" App="hello">
              <GML:ApplicationSchema xmlns="" xmlns:GML="http://www.sparxsystems.com/profiles/GML/1.0">GML App</GML:ApplicationSchema>
              <CityGML:ApplicationSchema xmlns="" xmlns:CityGML="http://www.sparxsystems.com/profiles/CityGML/1.0">CityGML App</CityGML:ApplicationSchema>
              <ApplicationSchema>App</ApplicationSchema>
            </SameElementName>
          </OverrideDefaultNamespacePrefix>
        XML
      end

      let(:oga_expected_xml) do
        input_xml.strip
      end

      it "expect to round-trips" do
        parsed = XmlMapping::OverrideDefaultNamespacePrefix.from_xml(input_xml)
        expected_xml = adapter_class.type == "oga" ? oga_expected_xml : input_xml
        expect(parsed.to_xml).to be_xml_equivalent_to(expected_xml)
      end
    end

    context "with same element and attribute name" do
      let(:xml_with_element) do
        <<~XML
          <ownedComment>
            <annotatedElement xmi:idref="ABC" xmlns:xmi="http://www.omg.org/spec/XMI/20131001" />
          </ownedComment>
        XML
      end

      let(:xml_with_attribute) do
        <<~XML
          <ownedComment annotatedElement="test2">
          </ownedComment>
        XML
      end

      let(:xml_with_same_name_attribute_and_element) do
        <<~XML
          <ownedComment annotatedElement="test2">
            <annotatedElement xmi:idref="ABC" xmlns:xmi="http://www.omg.org/spec/XMI/20131001" />
          </ownedComment>
        XML
      end

      let(:xml) do
        "<date type=\"published\"> End of December \n  <on>2020-01</on> Start of January \n</date>\n"
      end

      it "parse and serializes the input xml correctly # lutaml/issues/217" do
        parsed = XmlMapping::OwnedComment.from_xml(xml_with_element)
        serialized = parsed.to_xml

        expect(serialized).to be_xml_equivalent_to(xml_with_element.strip)
      end

      it "parse and serialize model correctly" do
        parsed = XmlMapping::OwnedComment.from_xml(xml_with_attribute)

        serialized = parsed.to_xml

        expect(serialized).to be_xml_equivalent_to(xml_with_attribute)
      end

      it "parse and serialize model correctly with both attribute and element" do
        parsed = XmlMapping::OwnedComment.from_xml(xml_with_same_name_attribute_and_element)
        serialized = parsed.to_xml

        expect(serialized).to be_xml_equivalent_to(xml_with_same_name_attribute_and_element)
      end

      it "testing parse element" do
        parsed = XmlMapping::Date.from_xml(xml)
        serialized = parsed.to_xml

        expect(serialized).to be_xml_equivalent_to(xml)
      end
    end

    context "with same name elements" do
      let(:input_xml) do
        <<~XML
          <SameElementName xmlns="http://www.omg.org/spec/XMI/20131001" App="hello">
            <GML:ApplicationSchema xmlns="" xmlns:GML="http://www.sparxsystems.com/profiles/GML/1.0">GML App</GML:ApplicationSchema>
            <CityGML:ApplicationSchema xmlns="" xmlns:CityGML="http://www.sparxsystems.com/profiles/CityGML/1.0">CityGML App</CityGML:ApplicationSchema>
            <ApplicationSchema>App</ApplicationSchema>
          </SameElementName>
        XML
      end

      let(:expected_order) do
        nokogiri_pattern = create_pattern_mapping([
                                                    ["Text", "text"],
                                                    ["Element",
                                                     "ApplicationSchema"],
                                                    ["Text", "text"],
                                                    ["Element",
                                                     "ApplicationSchema"],
                                                    ["Text", "text"],
                                                    ["Element",
                                                     "ApplicationSchema"],
                                                    ["Text", "text"],
                                                  ])

        oga_ox_pattern = create_pattern_mapping([
                                                  ["Element",
                                                   "ApplicationSchema"],
                                                  ["Element",
                                                   "ApplicationSchema"],
                                                  ["Element",
                                                   "ApplicationSchema"],
                                                ])

        {
          Lutaml::Model::Xml::NokogiriAdapter => nokogiri_pattern,
          Lutaml::Model::Xml::OxAdapter => oga_ox_pattern,
          Lutaml::Model::Xml::OgaAdapter => oga_ox_pattern,
        }
      end

      let(:parsed) do
        XmlMapping::SameNameDifferentNamespace.from_xml(input_xml)
      end

      def create_pattern_mapping(array)
        array.map do |type, text|
          Lutaml::Model::Xml::Element.new(type, text)
        end
      end

      it "citygml_application_schema should be correct" do
        expect(parsed.citygml_application_schema).to eq("CityGML App")
      end

      it "gml_application_schema should be correct" do
        expect(parsed.gml_application_schema).to eq("GML App")
      end

      it "application_schema should be correct" do
        expect(parsed.application_schema).to eq("App")
      end

      it "app should be correct" do
        expect(parsed.app).to eq("hello")
      end

      it "element_order should be correct" do
        expect(parsed.element_order).to eq(expected_order[adapter_class])
      end

      it "to_xml should be correct" do
        expect(parsed.to_xml).to be_xml_equivalent_to(input_xml)
      end
    end

    context "with elements have different prefixed namespaces" do
      before do
        mapping.root("XMI")
        mapping.namespace(XmiNamespace)
        mapping.map_element(
          "ApplicationSchema",
          to: :gml_application_schema,
          namespace: GmlNamespace,
        )
        mapping.map_element(
          "ApplicationSchema",
          to: :citygml_application_schema,
          namespace: CityGmlNamespace,
        )
        mapping.map_element(
          "ApplicationSchema",
          to: :citygml_application_schema,
          namespace: CgmlNamespace,
        )
      end

      it "maps elements correctly" do
        expect(mapping.elements[0].namespace_class).to eq(GmlNamespace)
        expect(mapping.elements[1].namespace_class).to eq(CityGmlNamespace)
        expect(mapping.elements[2].namespace_class).to eq(CgmlNamespace)
        expect(mapping.elements.size).to eq(3)
      end
    end

    context "with child having explicit namespaces" do
      let(:xml) do
        <<~XML.strip
          <WithChildExplicitNamespaceNil xmlns="http://parent-namespace">
            <DefaultNamespace xmlns="">default namespace text</DefaultNamespace>
            <cn:WithNamespace xmlns="" xmlns:cn="http://child-namespace">explicit namespace text</cn:WithNamespace>
            <pn:WithoutNamespace>without namespace text</pn:WithoutNamespace>
          </WithChildExplicitNamespaceNil>
        XML
      end

      let(:parsed) do
        XmlMapping::WithChildExplicitNamespace.from_xml(xml)
      end

      it "reads element with default namespace" do
        expect(parsed.with_default_namespace).to eq("default namespace text")
      end

      it "reads element with explicit namespace" do
        expect(parsed.with_namespace).to eq("explicit namespace text")
      end

      it "reads element without namespace" do
        # NOTE: mapping with namespace: nil, prefix: nil has differing adapter behavior:
        # - Nokogiri: Cannot parse element with parent namespace prefix, returns nil
        # - Ox/Oga: Can parse element with parent namespace prefix successfully
        if adapter_class == Lutaml::Model::Xml::NokogiriAdapter
          expect(parsed.without_namespace).to be_nil
        else
          expect(parsed.without_namespace).to eq("without namespace text")
        end
      end

      it "round-trips xml with child explicit namespace" do
        # Serialize the parsed model
        serialized = parsed.to_xml

        if adapter_class == Lutaml::Model::Xml::NokogiriAdapter
          # Nokogiri cannot parse the pn:WithoutNamespace element, so it's nil
          # and won't be in the serialized output. Verify other elements round-trip.
          reparsed = XmlMapping::WithChildExplicitNamespace.from_xml(serialized)
          expect(reparsed.with_default_namespace).to eq("default namespace text")
          expect(reparsed.with_namespace).to eq("explicit namespace text")
        else
          # Ox/Oga can parse the element successfully
          # With namespace scope minimization, namespace: nil produces xmlns=""
          # DefaultNamespace inherits parent (ParentNamespace is :qualified)
          expected_xml = <<~XML.strip
            <WithChildExplicitNamespaceNil xmlns="http://parent-namespace">
              <DefaultNamespace>default namespace text</DefaultNamespace>
              <cn:WithNamespace xmlns="" xmlns:cn="http://child-namespace">explicit namespace text</cn:WithNamespace>
              <WithoutNamespace xmlns="">without namespace text</WithoutNamespace>
            </WithChildExplicitNamespaceNil>
          XML
          expect(serialized).to be_xml_equivalent_to(expected_xml)
        end
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
        )
        mapping.map_element("color", to: :color, delegate: :glaze)
        mapping.map_element("finish", to: :finish, delegate: :glaze)
      end

      it "sets the namespace for individual elements" do
        expect(mapping.elements.size).to eq(3)
        expect(mapping.elements[0].namespace)
          .to eq("https://example.com/ceramic/1.2")
        # NOTE: String namespace API is deprecated, no namespace_class available
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
        )
        mapping.map_element("type", to: :type)
        mapping.map_element("color", to: :color, delegate: :glaze)
        mapping.map_element("finish", to: :finish, delegate: :glaze)
      end

      it "sets the namespace for individual attributes" do
        expect(mapping.attributes.size).to eq(1)
        expect(mapping.attributes[0].namespace)
          .to eq("https://example.com/ceramic/1.2")
        # NOTE: String namespace API is deprecated, no namespace_class available
      end
    end

    context "with nil element-level namespace" do
      let(:expected_xml) do
        <<~XML
          <ChildNamespaceNil xmlns="http://www.omg.org/spec/XMI/20131001">
            <ElementDefaultNamespace>Default namespace</ElementDefaultNamespace>
            <ElementNilNamespace xmlns="">No namespace</ElementNilNamespace>
            <new:ElementNewNamespace xmlns="" xmlns:new="http://www.omg.org/spec/XMI/20161001">New namespace</new:ElementNewNamespace>
          </ChildNamespaceNil>
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
        expect(model.to_xml).to be_xml_equivalent_to(expected_xml)
      end
    end

    context "with schemaLocation" do
      context "when mixed: false" do
        let(:xml) do
          '<p xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.opengis.net/gml/3.2 http://schemas.opengis.net/gml/3.2.1/gml.xsd"><p xmlns:xsi="http://another-instance" xsi:schemaLocation="http://www.opengis.net/gml/3.7"> Some text inside paragraph </p></p>'
        end

        it "contain schemaLocation attributes" do
          expect(Paragraph.from_xml(xml).to_xml).to be_xml_equivalent_to(xml)
        end

        it "prints warning if defined explicitly in class" do
          error_regex = /\[Lutaml::Model\] WARN: `schemaLocation` is handled by default\. No need to explicitly define at `xml_mapping_spec.rb:\d+`/

          expect do
            mapping.map_attribute("schemaLocation", to: :schema_location)
          end.to output(error_regex).to_stderr
        end
      end

      context "when mixed: true" do
        let(:xml) do
          '<schemaLocationOrdered xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.opengis.net/gml/3.2 http://schemas.opengis.net/gml/3.2.1/gml.xsd"><schemaLocationOrdered xmlns:xsi="http://another-instance" xsi:schemaLocation="http://www.opengis.net/gml/3.7"> Some text inside paragraph </schemaLocationOrdered></schemaLocationOrdered>'
        end

        let(:generated_xml) do
          XmlMapping::SchemaLocationOrdered.from_xml(xml).to_xml
        end

        it "contain schemaLocation attributes" do
          expect(generated_xml).to be_xml_equivalent_to(xml)
        end
      end
    end

    context "with multiple schemaLocations" do
      let(:nested_schema_location) do
        Lutaml::Model::SchemaLocation.new(
          schema_location: "http://www.opengis.net/gml/3.7 http://schemas.opengis.net/gml/3.7.1/gml.xsd http://www.isotc211.org/2005/gmd http://schemas.opengis.net/iso/19139/20070417/gmd/gmd.xsd",
          prefix: "xsi",
          namespace: "http://another-instance",
        )
      end

      let(:schema_location) do
        Lutaml::Model::SchemaLocation.new(
          schema_location: "http://www.opengis.net/gml/3.2 http://schemas.opengis.net/gml/3.2.1/gml.xsd http://www.w3.org/1999/xlink http://www.w3.org/1999/xlink.xsd",
          prefix: "xsi",
        )
      end

      let(:xml) do
        '<p xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.opengis.net/gml/3.2 http://schemas.opengis.net/gml/3.2.1/gml.xsd http://www.w3.org/1999/xlink http://www.w3.org/1999/xlink.xsd"><p xmlns:xsi="http://another-instance" xsi:schemaLocation="http://www.opengis.net/gml/3.7 http://schemas.opengis.net/gml/3.7.1/gml.xsd http://www.isotc211.org/2005/gmd http://schemas.opengis.net/iso/19139/20070417/gmd/gmd.xsd">Some text inside paragraph</p></p>'
      end

      context "when deserializing" do
        let(:parsed) { Paragraph.from_xml(xml) }

        it "parses correctly" do
          expect(parsed.schema_location.size).to eq(2)
          expect(parsed.schema_location[0]).to eq(schema_location[0])
          expect(parsed.schema_location[1]).to eq(schema_location[1])
        end

        it "parses nested correctly" do
          nested_p = parsed.paragraph

          expect(nested_p.schema_location.size).to eq(2)
          expect(nested_p.schema_location[0]).to eq(nested_schema_location[0])
          expect(nested_p.schema_location[1]).to eq(nested_schema_location[1])
        end
      end

      context "when serializing" do
        let(:paragraph) do
          Paragraph.new(
            schema_location: schema_location,
            paragraph: Paragraph.new(
              schema_location: nested_schema_location,
              text: ["Some text inside paragraph"],
            ),
          )
        end

        it "creates XML with multiple schemaLocations" do
          serialized = paragraph.to_xml
          expect(serialized).to be_xml_equivalent_to(xml)
        end
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
              <text>Building near ABC</text>
            </address>
          </person>
        XML
      end

      let(:expected_street) do
        if Lutaml::Model::Config.xml_adapter == Lutaml::Model::Xml::NokogiriAdapter
          "\n      <a>N</a>\n      <p>adf</p>\n    "
        else
          "<a>N</a><p>adf</p>"
        end
      end

      let(:model) { XmlMapping::Person.from_xml(input_xml) }

      it "expect to contain raw xml" do
        expect(model.address.street).to eq(expected_street)
        expect(model.address.city.strip).to eq("<a>M</a>")
      end
    end

    context "with element named `text`" do
      let(:input_xml) do
        <<~XML
          <address>
            <street>
              <a>N</a>
              <p>adf</p>
            </street>
            <city><a>M</a></city>
            <text>Building near ABC</text>
          </address>
        XML
      end

      let(:model) { XmlMapping::Address.from_xml(input_xml) }

      it "expect to contain raw xml" do
        expect(model.text).to eq("Building near ABC")
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
          expect(paragraph.to_xml).to be_xml_equivalent_to(expected_xml)
        end
      end
    end

    describe "#deep_dup" do
      let(:orig_mappings) do
        XmlMapping::ToBeDuplicated.mappings_for(:xml)
      end

      let(:dup_mappings) do
        orig_mappings.deep_dup
      end

      XmlMapping::WithMapAll.mappings_for(:xml).instance_variables.each do |var|
        it "duplicates #{var} correctly" do
          orig_mapping = XmlMapping::WithMapAll.mappings_for(:xml)
          dup_mappings = orig_mapping.deep_dup

          expect(orig_mapping.instance_variable_get(var))
            .to eq(dup_mappings.instance_variable_get(var))
        end
      end

      it "duplicates root_element" do
        orig_root = orig_mappings.root_element
        dup_root = dup_mappings.root_element

        expect(orig_root).to eq(dup_root)
        expect(orig_root.object_id).not_to eq(dup_root.object_id)
      end

      it "duplicates namespace_uri" do
        orig_namespace_uri = orig_mappings.namespace_uri
        dup_namespace_uri = dup_mappings.namespace_uri

        expect(orig_namespace_uri).to eq(dup_namespace_uri)
        expect(orig_namespace_uri.object_id)
          .not_to eq(dup_namespace_uri.object_id)
      end

      it "duplicates namespace_prefix" do
        orig_namespace_prefix = orig_mappings.namespace_prefix
        dup_namespace_prefix = dup_mappings.namespace_prefix

        expect(orig_namespace_prefix).to eq(dup_namespace_prefix)
        expect(orig_namespace_prefix.object_id)
          .not_to eq(dup_namespace_prefix.object_id)
      end

      context "when duplicating mapping" do
        let(:orig_mapping) { orig_mappings.mappings[0] }
        let(:dup_mapping) { dup_mappings.mappings[0] }

        it "duplicates custom_methods" do
          orig_custom_methods = orig_mapping.custom_methods
          dup_custom_methods = dup_mapping.custom_methods

          expect(orig_custom_methods).to eq(dup_custom_methods)
          expect(orig_custom_methods.object_id)
            .not_to eq(dup_custom_methods.object_id)
        end

        it "duplicates default_namespace" do
          orig_default_namespace = orig_mapping.default_namespace
          dup_default_namespace = dup_mapping.default_namespace

          expect(orig_default_namespace).to eq(dup_default_namespace)
          expect(orig_default_namespace.object_id)
            .not_to eq(dup_default_namespace.object_id)
        end

        it "duplicates delegate" do
          # `delegate` is symbol which are constant so object_id will be same
          expect(orig_mapping.delegate).to eq(dup_mapping.delegate)
        end

        it "duplicates mixed content" do
          # boolean value is constant so object_id will be same
          expect(orig_mapping.mixed_content).to eq(dup_mapping.mixed_content)
        end

        it "duplicates name" do
          orig_name = orig_mapping.name
          dup_name = dup_mapping.name

          expect(orig_name).to eq(dup_name)
          expect(orig_name.object_id).not_to eq(dup_name.object_id)
        end

        it "duplicates namespace" do
          orig_namespace = orig_mapping.namespace
          dup_namespace = dup_mapping.namespace

          expect(orig_namespace).to eq(dup_namespace)
          expect(orig_namespace.object_id).not_to eq(dup_namespace.object_id)
        end

        it "duplicates namespace_set" do
          # boolean value is constant so object_id will be same
          expect(orig_mapping.namespace_set?).to eq(dup_mapping.namespace_set?)
        end

        it "duplicates prefix" do
          orig_prefix = orig_mapping.prefix
          dup_prefix = dup_mapping.prefix

          expect(orig_prefix).to eq(dup_prefix)
          expect(orig_prefix.object_id).not_to eq(dup_prefix.object_id)
        end

        it "duplicates namespace_class" do
          # namespace_class should be properly duplicated
          expect(orig_mapping.namespace_class).to eq(dup_mapping.namespace_class)
        end

        it "duplicates render_nil" do
          # boolean value is constant so object_id will be same
          expect(orig_mapping.render_nil?).to eq(dup_mapping.render_nil?)
        end

        it "duplicates to" do
          # `to` is symbol which are constant so object_id will be same
          expect(orig_mapping.to).to eq(dup_mapping.to)
        end

        it "duplicates attribute" do
          # boolean value is constant so object_id will be same
          expect(orig_mappings.attributes.first.attribute?).to eq(dup_mappings.attributes.first.attribute?)
        end
      end
    end

    describe "#map_all" do
      context "when map_all is defined before any other mapping" do
        it "raise error when for map_element with map_all" do
          expect do
            XmlMapping::WithMapAll.xml do
              map_element "ele", to: :ele
            end
          end.to raise_error(
            StandardError,
            "map_element is not allowed, only map_attribute is allowed with map_all",
          )
        end

        it "raise error when for map_content with map_all" do
          expect do
            XmlMapping::WithMapAll.xml do
              map_content to: :text
            end
          end.to raise_error(
            StandardError,
            "map_content is not allowed, only map_attribute is allowed with map_all",
          )
        end

        it "does not raise error for map_attribute with map_all" do
          expect do
            XmlMapping::WithMapAll.xml do
              map_attribute "attr", to: :attr
            end
          end.not_to raise_error
        end
      end

      context "when map_all is defined after other mappings" do
        let(:error_message) { "map_all is not allowed with other mappings" }

        it "raise error when for map_element with map_all" do
          expect do
            XmlMapping::WithoutMapAll.xml do
              map_all to: :all_content
            end
          end.to raise_error(StandardError, error_message)
        end
      end

      context "with custom methods" do
        let(:inner_xml) do
          "Str<sub>2</sub>text<sup>1</sup>123"
        end

        let(:xml) do
          "<MapAllWithCustomMethod>#{inner_xml}</MapAllWithCustomMethod>"
        end

        let(:parsed) do
          XmlMapping::MapAllWithCustomMethod.from_xml(xml)
        end

        it "uses custom method when parsing XML" do
          expect(parsed.all_content).to eq("<div>#{inner_xml}</div>")
        end

        it "generates correct XML" do
          expect(parsed.to_xml.chomp).to be_xml_equivalent_to(xml)
        end
      end

      context "without custom methods" do
        let(:inner_xml) do
          if adapter_class.type == "ox"
            "Str<sub>2</sub>text<sup>1</sup>123"
          else
            "Str<sub>2</sub> text<sup>1</sup> 123"
          end
        end

        let(:xml) do
          "<WithMapAll>#{inner_xml}</WithMapAll>"
        end

        let(:parsed) do
          XmlMapping::WithMapAll.from_xml(xml)
        end

        it "maps all the content including tags" do
          expect(parsed.all_content).to eq(inner_xml)
        end

        it "round-trips xml" do
          expect(parsed.to_xml.chomp).to eq(xml)
        end
      end

      context "when nested content has map_all" do
        let(:description) do
          "I'm a <b>web developer</b> with <strong>years</strong> of <i>experience</i> in many programing languages. "
        end

        let(:xml) do
          <<~XML
            <WithNestedMapAll age="23">
              <name>John Doe</name>
              <description>#{description}</description>
            </WithNestedMapAll>
          XML
        end

        let(:parsed) do
          XmlMapping::WithNestedMapAll.from_xml(xml)
        end

        it "maps description correctly" do
          expect(parsed.description.all_content.strip).to eq(description.strip)
        end

        it "maps name correctly" do
          expect(parsed.name).to eq("John Doe")
        end

        it "maps age correctly" do
          expect(parsed.age).to eq(23)
        end

        it "round-trips xml" do
          expect(parsed.to_xml).to be_xml_equivalent_to(xml)
        end
      end

      context "when special char used in content with map all" do
        let(:xml) do
          <<~XML
            <SpecialCharContentWithMapAll>
              B <p>R&#x0026;C</p>
              C <p>J&#8212;C</p>
              O <p>A &amp; B </p>
              F <p>Z &#x00A9; </p>
            </SpecialCharContentWithMapAll>
          XML
        end

        let(:expected_nokogiri_xml) do
          <<~XML.strip
            <SpecialCharContentWithMapAll>
              B <p>R&amp;C</p>
              C <p>J—C</p>
              O <p>A &amp; B </p>
              F <p>Z © </p>
            </SpecialCharContentWithMapAll>
          XML
        end

        let(:expected_oga_xml) do
          <<~XML.strip
            <SpecialCharContentWithMapAll>
              B <p>R&amp;C</p>
              C <p>J—C</p>
              O <p>A &amp; B </p>
              F <p>Z © </p></SpecialCharContentWithMapAll>
          XML
        end

        let(:expected_ox_xml) do
          "<SpecialCharContentWithMapAll> " \
            "B <p>R&amp;C</p> " \
            "C <p>J—C</p> " \
            "O <p>A &#038; B </p> " \
            "F <p>Z © </p>" \
            "</SpecialCharContentWithMapAll>\n"
        end

        let(:expected_xml) do
          if adapter_class.type == "ox"
            expected_ox_xml
          elsif adapter_class.type == "oga"
            expected_oga_xml
          else
            expected_nokogiri_xml
          end
        end

        it "round-trips xml" do
          parsed = XmlMapping::SpecialCharContentWithMapAll.from_xml(xml)
          expect(parsed.to_xml).to be_xml_equivalent_to(expected_xml)
        end
      end

      context "when mixed content is true and child is content_mapping" do
        let(:xml) do
          <<~XML
            <schema xmlns="http://www.w3.org/2001/XMLSchema">
              <documentation>asdf</documentation>
            </schema>
          XML
        end

        let(:generated_xml) do
          XmlMapping::Schema.from_xml(xml).to_xml
        end

        it "round-trips xml" do
          expect(generated_xml).to be_xml_equivalent_to(xml)
        end
      end
    end

    describe "validation errors" do
      # rubocop:disable all
      let(:mapping) { Lutaml::Model::Xml::Mapping.new }
      # rubocop:enable all

      it "raises error when neither :to nor :with provided" do
        expect do
          mapping.map_element("test")
        end.to raise_error(
          Lutaml::Model::IncorrectMappingArgumentsError,
          ":to or :with argument is required for mapping 'test'",
        )
      end

      it "raises error when :with is missing :to or :from keys" do
        expect do
          mapping.map_element("test", with: { to: "value" })
        end.to raise_error(
          Lutaml::Model::IncorrectMappingArgumentsError,
          ":with argument for mapping 'test' requires :to and :from keys",
        )
      end

      it "does not raise error when :to is provided" do
        expect do
          mapping.map_element("test", to: :test, with: { from: "value" })
        end.not_to raise_error
      end

      describe "map_attribute validations" do
        it "raises error for invalid :with argument" do
          expect do
            mapping.map_attribute("test", with: { from: "value" })
          end.to raise_error(
            Lutaml::Model::IncorrectMappingArgumentsError,
            ":with argument for mapping 'test' requires :to and :from keys",
          )
        end

        it "does not raise error if to is provided" do
          expect do
            mapping.map_attribute("test", to: :test, with: { from: "value" })
          end.not_to raise_error
        end
      end

      describe "map_content validations" do
        it "raises error when no :to provided" do
          expect do
            mapping.map_content
          end.to raise_error(
            Lutaml::Model::IncorrectMappingArgumentsError,
            ":to or :with argument is required for mapping 'content'",
          )
        end
      end
    end
  end

  describe Lutaml::Model::Xml::NokogiriAdapter do
    it_behaves_like "having XML Mappings", described_class
  end

  describe Lutaml::Model::Xml::OxAdapter do
    it_behaves_like "having XML Mappings", described_class
  end

  describe Lutaml::Model::Xml::OgaAdapter do
    it_behaves_like "having XML Mappings", described_class
  end
end
