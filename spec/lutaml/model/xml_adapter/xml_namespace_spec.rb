require "spec_helper"
require "lutaml/model/xml/nokogiri_adapter"
require "lutaml/model/xml/ox_adapter"
require "lutaml/model/xml/oga_adapter"
require "lutaml/model"
require_relative "../../../support/xml_mapping_namespaces"

module XmlNamespaceSpec
  class TestModelNoPrefix < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      element "test"
      namespace TestNamespaceNoPrefix
      map_element "name", to: :name
    end
  end

  class TestModelWithPrefix < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      element "test"
      namespace TestNamespace
      map_element "name", to: :name
    end
  end

  class SamplePrefixedNamespacedModel < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :lang, :string
    attribute :name, :string, default: -> { "Anonymous" }
    attribute :age, :integer, default: -> { 18 }

    xml do
      element "SamplePrefixedNamespacedModel"
      namespace FooNamespace

      map_attribute "id", to: :id
      map_attribute "lang", to: :lang,
                            namespace: XmlLangNamespace

      map_element "Name", to: :name, namespace: BarNamespace
      map_element "Age", to: :age, namespace: BazNamespace
    end
  end

  class NamespaceNilPrefixedNamespaced < Lutaml::Model::Serializable
    attribute :namespace_model, SamplePrefixedNamespacedModel

    xml do
      element "NamespaceNil"
      map_element "SamplePrefixedNamespacedModel", to: :namespace_model,
                                                    namespace: nil
    end
  end

  class SampleDefaultNamespacedModel < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :lang, :string
    attribute :name, :string, default: -> { "Anonymous" }
    attribute :age, :integer, default: -> { 18 }

    xml do
      element "SampleDefaultNamespacedModel"
      namespace FooNamespace

      map_attribute "id", to: :id
      map_attribute "lang", to: :lang,
                            namespace: XmlLangNamespace

      map_element "Name", to: :name, namespace: BarNamespace
      map_element "Age", to: :age, namespace: BazNamespace
    end
  end

  class NamespaceNilDefaultNamespaced < Lutaml::Model::Serializable
    attribute :namespace_model, SampleDefaultNamespacedModel

    xml do
      element "NamespaceNil"
      map_element "SampleDefaultNamespacedModel", to: :namespace_model,
                                                  namespace: nil
    end
  end

  class Body < Lutaml::Model::Serializable
    attribute :paragraph, :string

    xml do
      map_element "p", to: :paragraph
    end
  end

  class Element < Lutaml::Model::Serializable
    attribute :text, :string
    xml do
      element "test-element"
      namespace TestSchemasNamespace
      map_content to: :text
    end
  end

  class Front < Lutaml::Model::Serializable
    attribute :test_element, Element

    xml do
      namespace TestSchemasNamespace
      map_element "test-element", to: :test_element
    end
  end

  class Article < Lutaml::Model::Serializable
    attribute :front, Front
    attribute :body, Body

    xml do
      element "article"
      map_element "front", to: :front, namespace: TestSchemasNamespace
      map_element "body", to: :body
    end
  end

  class OwnedEnd < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :type, :string
    attribute :uml_type, :string

    xml do
      element "ownedEnd"

      map_attribute "id", to: :id,
                          namespace: XmiNamespace
      map_attribute "type", to: :type,
                            namespace: XmiNamespace
      map_attribute "type", to: :uml_type
    end
  end

  # Models for testing namespace inheritance optimization (UnitsML scenario)
  class UnitSystem < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :type, :string

    xml do
      element "UnitSystem"
      namespace UnitsNamespace
      map_attribute "name", to: :name
      map_attribute "type", to: :type
    end
  end

  class UnitName < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      element "UnitName"
      namespace UnitsNamespace
      map_content to: :value
    end
  end

  class EnumeratedRootUnit < Lutaml::Model::Serializable
    attribute :unit, :string
    attribute :prefix, :string

    xml do
      element "EnumeratedRootUnit"
      namespace UnitsNamespace
      map_attribute "unit", to: :unit
      map_attribute "prefix", to: :prefix
    end
  end

  class RootUnits < Lutaml::Model::Serializable
    attribute :enumerated_root_units, EnumeratedRootUnit, collection: true

    xml do
      element "RootUnits"
      namespace UnitsNamespace
      map_element "EnumeratedRootUnit", to: :enumerated_root_units
    end
  end

  class Unit < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :unit_system, UnitSystem
    attribute :unit_name, UnitName
    attribute :root_units, RootUnits

    xml do
      element "Unit"
      namespace UnitsNamespace
      map_attribute "id", to: :id
      map_element "UnitSystem", to: :unit_system
      map_element "UnitName", to: :unit_name
      map_element "RootUnits", to: :root_units
    end
  end

  # Models for testing mixed namespaces
  class MathContent < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      element "math"
      namespace MathMlNamespace
      map_content to: :value
    end
  end

  class UnitSymbol < Lutaml::Model::Serializable
    attribute :type, :string
    attribute :math, MathContent

    xml do
      element "UnitSymbol"
      namespace UnitsNamespace
      map_attribute "type", to: :type
      map_element "math", to: :math
    end
  end

  class UnitWithMath < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :unit_symbol, UnitSymbol

    xml do
      element "Unit"
      namespace UnitsNamespace
      map_attribute "id", to: :id
      map_element "UnitSymbol", to: :unit_symbol
    end
  end
end

RSpec.describe "XmlNamespace" do
  shared_examples "XML serialization with namespace" do |model_class, xml_string|
    it "serializes to XML" do
      model = model_class.new(name: "Test Name")
      expect(model.to_xml).to be_xml_equivalent_to(xml_string)
    end

    it "deserializes from XML" do
      model = model_class.from_xml(xml_string)
      expect(model.name).to eq("Test Name")
    end
  end

  shared_examples "an XML namespace parser" do |adapter_class|
    around do |example|
      old_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_class
      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = old_adapter
    end

    context "with no prefix" do
      it_behaves_like "XML serialization with namespace",
                      XmlNamespaceSpec::TestModelNoPrefix,
                      '<test xmlns="http://example.com/test"><name>Test Name</name></test>'
    end

    context "with prefix" do
      it_behaves_like "XML serialization with namespace",
                      XmlNamespaceSpec::TestModelWithPrefix,
                      '<test xmlns="http://example.com/test"><name>Test Name</name></test>'
    end

    context "with prefixed namespace" do
      let(:attributes) { { name: "John Doe", age: 30 } }
      let(:model) { XmlNamespaceSpec::SamplePrefixedNamespacedModel.new(attributes) }

      let(:xml) do
        <<~XML
          <SamplePrefixedNamespacedModel xmlns="http://example.com/foo">
            <bar:Name xmlns="" xmlns:bar="http://example.com/bar">John Doe</bar:Name>
            <baz:Age xmlns="" xmlns:baz="http://example.com/baz">30</baz:Age>
          </SamplePrefixedNamespacedModel>
        XML
      end

      let(:xml_with_lang) do
        <<~XML
          <SamplePrefixedNamespacedModel xmlns="http://example.com/foo" xml:lang="en" xmlns:xml="http://example.com/xml">
            <bar:Name xmlns="" xmlns:bar="http://example.com/bar">John Doe</bar:Name>
            <baz:Age xmlns="" xmlns:baz="http://example.com/baz">30</baz:Age>
          </SamplePrefixedNamespacedModel>
        XML
      end

      it "serializes to XML" do
        expect(model.to_xml).to be_xml_equivalent_to(xml)
      end

      it "deserializes from XML" do
        new_model = XmlNamespaceSpec::SamplePrefixedNamespacedModel.from_xml(xml)
        expect(new_model.name).to eq("John Doe")
        expect(new_model.age).to eq(30)
      end

      it "round-trips if namespace is set" do
        doc = XmlNamespaceSpec::SamplePrefixedNamespacedModel.from_xml(xml_with_lang)
        generated_xml = doc.to_xml
        expect(generated_xml).to be_xml_equivalent_to(xml_with_lang)
      end

      it "round-trips with same namespace hoisting setup by keeping input declaration plan" do
        # NOTE: Current implementation declares namespaces locally (close to usage)
        # rather than hoisting to root - both are W3C compliant
        xml = <<~XML
          <NamespaceNil>
            <SamplePrefixedNamespacedModel xmlns="http://example.com/foo" xml:lang="en" xmlns:xml="http://example.com/xml">
              <bar:Name xmlns="" xmlns:bar="http://example.com/bar">John Doe</bar:Name>
              <baz:Age xmlns="" xmlns:baz="http://example.com/baz">30</baz:Age>
            </SamplePrefixedNamespacedModel>
          </NamespaceNil>
        XML

        doc = XmlNamespaceSpec::NamespaceNilPrefixedNamespaced.from_xml(xml)
        generated_xml = doc.to_xml

        puts "********"
        puts generated_xml
        puts "--------"
        puts xml
        puts "********"
        expect(generated_xml).to be_xml_equivalent_to(xml)
      end
    end

    context "with default namespace" do
      let(:attributes) { { name: "Jane Smith", age: 25 } }
      let(:model) { XmlNamespaceSpec::SampleDefaultNamespacedModel.new(attributes) }

      it "serializes to XML" do
        expected_xml = <<~XML
          <SampleDefaultNamespacedModel xmlns="http://example.com/foo">
            <bar:Name xmlns="" xmlns:bar="http://example.com/bar">Jane Smith</bar:Name>
            <baz:Age xmlns="" xmlns:baz="http://example.com/baz">25</baz:Age>
          </SampleDefaultNamespacedModel>
        XML

        expect(model.to_xml).to be_xml_equivalent_to(expected_xml)
      end

      it "deserializes from XML" do
        xml = <<~XML
          <SampleDefaultNamespacedModel xmlns="http://example.com/foo">
            <bar:Name xmlns="" xmlns:bar="http://example.com/bar">Jane Smith</bar:Name>
            <baz:Age xmlns="" xmlns:baz="http://example.com/baz">25</baz:Age>
          </SampleDefaultNamespacedModel>
        XML

        new_model = XmlNamespaceSpec::SampleDefaultNamespacedModel.from_xml(xml)
        expect(new_model.name).to eq("Jane Smith")
        expect(new_model.age).to eq(25)
      end

      it "round-trips if namespace is set" do
        xml = <<~XML
          <SampleDefaultNamespacedModel xmlns="http://example.com/foo" xml:lang="en" xmlns:xml="http://example.com/xml">
            <bar:Name xmlns="" xmlns:bar="http://example.com/bar">Jane Smith</bar:Name>
            <baz:Age xmlns="" xmlns:baz="http://example.com/baz">25</baz:Age>
          </SampleDefaultNamespacedModel>
        XML

        doc = XmlNamespaceSpec::SampleDefaultNamespacedModel.from_xml(xml)
        generated_xml = doc.to_xml
        expect(generated_xml).to be_xml_equivalent_to(xml)
      end

      it "round-trips if namespace is set to nil in parent" do
        xml = <<~XML
          <NamespaceNil>
            <SampleDefaultNamespacedModel xmlns="http://example.com/foo" xml:lang="en" xmlns:xml="http://example.com/xml">
              <bar:Name xmlns="" xmlns:bar="http://example.com/bar">Jane Smith</bar:Name>
              <baz:Age xmlns="" xmlns:baz="http://example.com/baz">25</baz:Age>
            </SampleDefaultNamespacedModel>
          </NamespaceNil>
        XML

        doc = XmlNamespaceSpec::NamespaceNilDefaultNamespaced.from_xml(xml)
        generated_xml = doc.to_xml
        expect(generated_xml).to be_xml_equivalent_to(xml)
      end
    end

    context "when custom namespace is used" do
      let(:xml_input) do
        <<~XML
          <article>
            <test:front xmlns:test="http://www.test.com/schemas/test/1.0/">
              <test:test-element>Text Here</test:test-element>
            </test:front>
            <body>
              <p>This is a paragraph</p>
            </body>
          </article>
        XML
      end

      let(:expected_output) do
        <<~XML
          <article>
            <front xmlns="http://www.test.com/schemas/test/1.0/">
              <test-element>Text Here</test-element>
            </front>
            <body>
              <p>This is a paragraph</p>
            </body>
          </article>
        XML
      end

      describe "XML serialization" do
        it "correctly deserializes from XML" do
          article = XmlNamespaceSpec::Article.from_xml(xml_input)
          expect(article.body.paragraph).to eq("This is a paragraph")
        end

        it "round-trips XML" do
          article = XmlNamespaceSpec::Article.from_xml(xml_input)
          output_xml = article.to_xml(pretty: true)

          expect(output_xml).to be_xml_equivalent_to(expected_output)
        end
      end
    end

    context "when two attributes have same name but different namespace" do
      let(:xml_input) do
        <<~XML
          <ownedEnd xmlns:xmi="http://www.omg.org/spec/XMI/20131001"
                    xmi:type="xmi_type"
                    xmi:id="my_id"
                    type="test" />
        XML
      end

      describe "XML serialization" do
        it "correctly deserializes from XML" do
          owned_end = XmlNamespaceSpec::OwnedEnd.from_xml(xml_input)

          expect(owned_end.id).to eq("my_id")
          expect(owned_end.type).to eq("xmi_type")
          expect(owned_end.uml_type).to eq("test")
        end

        it "correctly serializes to XML" do
          owned_end = XmlNamespaceSpec::OwnedEnd.new(
            id: "my_id",
            type: "xmi_type",
            uml_type: "test",
          )

          puts "********"
          puts owned_end.to_xml
          puts "********"

          expect(owned_end.to_xml).to be_xml_equivalent_to(xml_input)
        end

        it "round-trips XML" do
          owned_end = XmlNamespaceSpec::OwnedEnd.from_xml(xml_input)
          output_xml = owned_end.to_xml

          expect(output_xml).to be_xml_equivalent_to(xml_input)
        end
      end
    end

    context "when nested elements share the same namespace" do
      let(:unit_system) { XmlNamespaceSpec::UnitSystem.new(name: "SI", type: "SI_derived") }
      let(:unit_name) { XmlNamespaceSpec::UnitName.new(value: "meter") }
      let(:meter_unit) { XmlNamespaceSpec::EnumeratedRootUnit.new(unit: "meter") }
      let(:gram_unit) { XmlNamespaceSpec::EnumeratedRootUnit.new(unit: "gram", prefix: "k") }
      let(:root_units) do
        XmlNamespaceSpec::RootUnits.new(enumerated_root_units: [meter_unit, gram_unit])
      end
      let(:unit) do
        XmlNamespaceSpec::Unit.new(
          id: "U_m",
          unit_system: unit_system,
          unit_name: unit_name,
          root_units: root_units,
        )
      end

      let(:expected_xml) do
        <<~XML
          <Unit xmlns="https://schema.example.org/units/1.0" id="U_m">
            <UnitSystem name="SI" type="SI_derived"/>
            <UnitName>meter</UnitName>
            <RootUnits>
              <EnumeratedRootUnit unit="meter"/>
              <EnumeratedRootUnit unit="gram" prefix="k"/>
            </RootUnits>
          </Unit>
        XML
      end

      it "declares xmlns only once on the root element" do
        xml = unit.to_xml
        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "does not repeat xmlns on child elements with same namespace" do
        xml = unit.to_xml

        # Count xmlns declarations for the units namespace
        xmlns_count = xml.scan('xmlns="https://schema.example.org/units/1.0"').size

        expect(xmlns_count).to eq(1),
                               "Expected exactly 1 xmlns declaration, found #{xmlns_count}"
      end

      it "deserializes correctly from XML with inherited namespace" do
        parsed = XmlNamespaceSpec::Unit.from_xml(expected_xml)

        expect(parsed.id).to eq("U_m")
        expect(parsed.unit_system.name).to eq("SI")
        expect(parsed.unit_system.type).to eq("SI_derived")
        expect(parsed.unit_name.value).to eq("meter")
        expect(parsed.root_units.enumerated_root_units.size).to eq(2)
        expect(parsed.root_units.enumerated_root_units[0].unit).to eq("meter")
        expect(parsed.root_units.enumerated_root_units[1].unit).to eq("gram")
        expect(parsed.root_units.enumerated_root_units[1].prefix).to eq("k")
      end

      it "round-trips XML with namespace inheritance" do
        xml = unit.to_xml
        parsed = XmlNamespaceSpec::Unit.from_xml(xml)
        regenerated_xml = parsed.to_xml

        expect(regenerated_xml).to be_xml_equivalent_to(expected_xml)
      end
    end

    context "when mixing different namespaces" do
      let(:math) { XmlNamespaceSpec::MathContent.new(value: "x+y") }
      let(:unit_symbol) { XmlNamespaceSpec::UnitSymbol.new(type: "MathML", math: math) }
      let(:unit_with_math) do
        XmlNamespaceSpec::UnitWithMath.new(id: "U_m.kg-2", unit_symbol: unit_symbol)
      end

      let(:expected_xml) do
        <<~XML
          <Unit xmlns="https://schema.example.org/units/1.0" id="U_m.kg-2">
            <UnitSymbol type="MathML">
              <math xmlns="http://www.w3.org/1998/Math/MathML">x+y</math>
            </UnitSymbol>
          </Unit>
        XML
      end

      it "declares different namespaces correctly" do
        xml = unit_with_math.to_xml
        expect(xml).to be_xml_equivalent_to(expected_xml)
      end

      it "round-trips XML with mixed namespaces" do
        xml = unit_with_math.to_xml
        parsed = XmlNamespaceSpec::UnitWithMath.from_xml(xml)

        expect(parsed.id).to eq("U_m.kg-2")
        expect(parsed.unit_symbol&.type).to eq("MathML")
        expect(parsed.unit_symbol&.math&.value).to eq("x+y")

        regenerated_xml = parsed.to_xml
        expect(regenerated_xml).to be_xml_equivalent_to(expected_xml)
      end
    end
  end

  describe Lutaml::Model::Xml::NokogiriAdapter do
    it_behaves_like "an XML namespace parser", described_class
  end

  describe Lutaml::Model::Xml::OxAdapter do
    it_behaves_like "an XML namespace parser", described_class
  end

  describe Lutaml::Model::Xml::OgaAdapter do
    it_behaves_like "an XML namespace parser", described_class
  end
end
