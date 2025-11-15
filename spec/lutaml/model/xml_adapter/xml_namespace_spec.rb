require "spec_helper"
require "lutaml/model/xml/nokogiri_adapter"
require "lutaml/model/xml/ox_adapter"
require "lutaml/model/xml/oga_adapter"
require "lutaml/model"

RSpec.describe "XmlNamespace" do
  shared_context "with XML namespace models" do
    class TestModelNoPrefix < Lutaml::Model::Serializable
      attribute :name, :string

      xml do
        root "test"
        namespace "http://example.com/test", "test"
        map_element "name", to: :name
      end
    end

    class TestModelWithPrefix < Lutaml::Model::Serializable
      attribute :name, :string

      xml do
        root "test"
        namespace "http://example.com/test", "test"
        map_element "name", to: :name
      end
    end

    class SamplePrefixedNamespacedModel < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :lang, :string
      attribute :name, :string, default: -> { "Anonymous" }
      attribute :age, :integer, default: -> { 18 }

      xml do
        root "SamplePrefixedNamespacedModel"
        namespace "http://example.com/foo", "foo"

        map_attribute "id", to: :id
        map_attribute "lang", to: :lang,
                              prefix: "xml",
                              namespace: "http://example.com/xml"

        map_element "Name", to: :name, prefix: "bar", namespace: "http://example.com/bar"
        map_element "Age", to: :age, prefix: "baz", namespace: "http://example.com/baz"
      end
    end

    class NamespaceNilPrefixedNamespaced < Lutaml::Model::Serializable
      attribute :namespace_model, SamplePrefixedNamespacedModel

      xml do
        root "NamespaceNil"
        map_element "SamplePrefixedNamespacedModel", to: :namespace_model,
                                                     namespace: nil,
                                                     prefix: nil
      end
    end

    class SampleDefaultNamespacedModel < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :lang, :string
      attribute :name, :string, default: -> { "Anonymous" }
      attribute :age, :integer, default: -> { 18 }

      xml do
        root "SampleDefaultNamespacedModel"
        namespace "http://example.com/foo"

        map_attribute "id", to: :id
        map_attribute "lang", to: :lang,
                              prefix: "xml",
                              namespace: "http://example.com/xml"

        map_element "Name", to: :name, prefix: "bar", namespace: "http://example.com/bar"
        map_element "Age", to: :age, prefix: "baz", namespace: "http://example.com/baz"
      end
    end

    class NamespaceNilDefaultNamespaced < Lutaml::Model::Serializable
      attribute :namespace_model, SampleDefaultNamespacedModel

      xml do
        root "NamespaceNil"
        map_element "SampleDefaultNamespacedModel", to: :namespace_model,
                                                    namespace: nil,
                                                    prefix: nil
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
        root "test-element"
        namespace "http://www.test.com/schemas/test/1.0/", "test"
        map_content to: :text
      end
    end

    class Front < Lutaml::Model::Serializable
      attribute :test_element, Element

      xml do
        namespace "http://www.test.com/schemas/test/1.0/", "test"
        map_element "test-element", to: :test_element
      end
    end

    class Article < Lutaml::Model::Serializable
      attribute :front, Front
      attribute :body, Body

      xml do
        root "article"
        map_element "front", to: :front, prefix: "test", namespace: "http://www.test.com/schemas/test/1.0/"
        map_element "body", to: :body
      end
    end

    class OwnedEnd < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :type, :string
      attribute :uml_type, :string

      xml do
        root "ownedEnd"

        map_attribute "id", to: :id,
                            namespace: "http://www.omg.org/spec/XMI/20131001", prefix: "xmi"
        map_attribute "type", to: :type,
                              namespace: "http://www.omg.org/spec/XMI/20131001", prefix: "xmi"
        map_attribute "type", to: :uml_type
      end
    end

    # Models for testing namespace inheritance optimization (UnitsML scenario)
    class UnitSystem < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :type, :string

      xml do
        root "UnitSystem"
        namespace "https://schema.example.org/units/1.0"
        map_attribute "name", to: :name
        map_attribute "type", to: :type
      end
    end

    class UnitName < Lutaml::Model::Serializable
      attribute :value, :string

      xml do
        root "UnitName"
        namespace "https://schema.example.org/units/1.0"
        map_content to: :value
      end
    end

    class EnumeratedRootUnit < Lutaml::Model::Serializable
      attribute :unit, :string
      attribute :prefix, :string

      xml do
        root "EnumeratedRootUnit"
        namespace "https://schema.example.org/units/1.0"
        map_attribute "unit", to: :unit
        map_attribute "prefix", to: :prefix
      end
    end

    class RootUnits < Lutaml::Model::Serializable
      attribute :enumerated_root_units, EnumeratedRootUnit, collection: true

      xml do
        root "RootUnits"
        namespace "https://schema.example.org/units/1.0"
        map_element "EnumeratedRootUnit", to: :enumerated_root_units
      end
    end

    class Unit < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :unit_system, UnitSystem
      attribute :unit_name, UnitName
      attribute :root_units, RootUnits

      xml do
        root "Unit"
        namespace "https://schema.example.org/units/1.0"
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
        root "math"
        namespace "http://www.w3.org/1998/Math/MathML"
        map_content to: :value
      end
    end

    class UnitSymbol < Lutaml::Model::Serializable
      attribute :type, :string
      attribute :math, MathContent

      xml do
        root "UnitSymbol"
        namespace "https://schema.example.org/units/1.0"
        map_attribute "type", to: :type
        map_element "math", to: :math
      end
    end

    class UnitWithMath < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :unit_symbol, UnitSymbol

      xml do
        root "Unit"
        namespace "https://schema.example.org/units/1.0"
        map_attribute "id", to: :id
        map_element "UnitSymbol", to: :unit_symbol
      end
    end
  end

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
    include_context "with XML namespace models"

    around do |example|
      old_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_class
      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = old_adapter
    end

    context "with no prefix" do
      it_behaves_like "XML serialization with namespace",
                      TestModelNoPrefix,
                      '<test xmlns="http://example.com/test"><name>Test Name</name></test>'
    end

    context "with prefix" do
      it_behaves_like "XML serialization with namespace",
                      TestModelWithPrefix,
                      '<test:test xmlns:test="http://example.com/test"><test:name>Test Name</test:name></test:test>'
    end

    context "with prefixed namespace" do
      let(:attributes) { { name: "John Doe", age: 30 } }
      let(:model) { SamplePrefixedNamespacedModel.new(attributes) }

      let(:xml) do
        <<~XML
          <foo:SamplePrefixedNamespacedModel xmlns:foo="http://example.com/foo" xmlns:bar="http://example.com/bar" xmlns:baz="http://example.com/baz">
            <bar:Name>John Doe</bar:Name>
            <baz:Age>30</baz:Age>
          </foo:SamplePrefixedNamespacedModel>
        XML
      end

      let(:xml_with_lang) do
        <<~XML
          <foo:SamplePrefixedNamespacedModel xml:lang="en" xmlns:foo="http://example.com/foo" xmlns:bar="http://example.com/bar" xmlns:baz="http://example.com/baz">
            <bar:Name>John Doe</bar:Name>
            <baz:Age>30</baz:Age>
          </foo:SamplePrefixedNamespacedModel>
        XML
      end

      it "serializes to XML" do
        expect(model.to_xml).to be_xml_equivalent_to(xml)
      end

      it "deserializes from XML" do
        new_model = SamplePrefixedNamespacedModel.from_xml(xml)
        expect(new_model.name).to eq("John Doe")
        expect(new_model.age).to eq(30)
      end

      it "round-trips if namespace is set" do
        doc = SamplePrefixedNamespacedModel.from_xml(xml_with_lang)
        generated_xml = doc.to_xml
        expect(generated_xml).to be_xml_equivalent_to(xml_with_lang)
      end

      it "round-trips if namespace is set to nil in parent" do
        xml = <<~XML
          <NamespaceNil xmlns:foo="http://example.com/foo" xmlns:bar="http://example.com/bar" xmlns:baz="http://example.com/baz">
            <SamplePrefixedNamespacedModel xml:lang="en">
              <bar:Name>John Doe</bar:Name>
              <baz:Age>30</baz:Age>
            </SamplePrefixedNamespacedModel>
          </NamespaceNil>
        XML

        doc = NamespaceNilPrefixedNamespaced.from_xml(xml)
        generated_xml = doc.to_xml
        expect(generated_xml).to be_xml_equivalent_to(xml)
      end
    end

    context "with default namespace" do
      let(:attributes) { { name: "Jane Smith", age: 25 } }
      let(:model) { SampleDefaultNamespacedModel.new(attributes) }

      it "serializes to XML" do
        expected_xml = <<~XML
          <SampleDefaultNamespacedModel xmlns="http://example.com/foo" xmlns:bar="http://example.com/bar" xmlns:baz="http://example.com/baz">
            <bar:Name>Jane Smith</bar:Name>
            <baz:Age>25</baz:Age>
          </SampleDefaultNamespacedModel>
        XML

        expect(model.to_xml).to be_xml_equivalent_to(expected_xml)
      end

      it "deserializes from XML" do
        xml = <<~XML
          <SampleDefaultNamespacedModel xmlns="http://example.com/foo" xmlns:bar="http://example.com/bar" xmlns:baz="http://example.com/baz">
            <bar:Name>Jane Smith</bar:Name>
            <baz:Age>25</baz:Age>
          </SampleDefaultNamespacedModel>
        XML

        new_model = SampleDefaultNamespacedModel.from_xml(xml)
        expect(new_model.name).to eq("Jane Smith")
        expect(new_model.age).to eq(25)
      end

      it "round-trips if namespace is set" do
        xml = <<~XML
          <SampleDefaultNamespacedModel xml:lang="en" xmlns="http://example.com/foo" xmlns:bar="http://example.com/bar" xmlns:baz="http://example.com/baz">
            <bar:Name>Jane Smith</bar:Name>
            <baz:Age>25</baz:Age>
          </SampleDefaultNamespacedModel>
        XML

        doc = SampleDefaultNamespacedModel.from_xml(xml)
        generated_xml = doc.to_xml
        expect(generated_xml).to be_xml_equivalent_to(xml)
      end

      it "round-trips if namespace is set to nil in parent" do
        xml = <<~XML
          <NamespaceNil xmlns:bar="http://example.com/bar" xmlns:baz="http://example.com/baz">
            <SampleDefaultNamespacedModel xml:lang="en">
              <bar:Name>Jane Smith</bar:Name>
              <baz:Age>25</baz:Age>
            </SampleDefaultNamespacedModel>
          </NamespaceNil>
        XML

        doc = NamespaceNilDefaultNamespaced.from_xml(xml)
        generated_xml = doc.to_xml
        expect(generated_xml).to be_xml_equivalent_to(xml)
      end
    end

    context "when custom namespace is used" do
      let(:xml_input) do
        <<~XML
          <article xmlns:test="http://www.test.com/schemas/test/1.0/">
            <test:front>
              <test:test-element>Text Here</test:test-element>
            </test:front>
            <body>
              <p>This is a paragraph</p>
            </body>
          </article>
        XML
      end

      describe "XML serialization" do
        it "correctly deserializes from XML" do
          article = Article.from_xml(xml_input)
          expect(article.body.paragraph).to eq("This is a paragraph")
        end

        it "round-trips XML" do
          article = Article.from_xml(xml_input)
          output_xml = article.to_xml(pretty: true)

          expect(output_xml).to be_xml_equivalent_to(xml_input)
        end
      end
    end

    context "when two attributes have same name but different prefix" do
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
          owned_end = OwnedEnd.from_xml(xml_input)

          expect(owned_end.id).to eq("my_id")
          expect(owned_end.type).to eq("xmi_type")
          expect(owned_end.uml_type).to eq("test")
        end

        it "correctly serializes to XML" do
          owned_end = OwnedEnd.new(
            id: "my_id",
            type: "xmi_type",
            uml_type: "test",
          )

          expect(owned_end.to_xml).to be_xml_equivalent_to(xml_input)
        end

        it "round-trips XML" do
          owned_end = OwnedEnd.from_xml(xml_input)
          output_xml = owned_end.to_xml

          expect(output_xml).to be_xml_equivalent_to(xml_input)
        end
      end
    end

    context "when nested elements share the same namespace" do
      let(:unit_system) { UnitSystem.new(name: "SI", type: "SI_derived") }
      let(:unit_name) { UnitName.new(value: "meter") }
      let(:meter_unit) { EnumeratedRootUnit.new(unit: "meter") }
      let(:gram_unit) { EnumeratedRootUnit.new(unit: "gram", prefix: "k") }
      let(:root_units) do
        RootUnits.new(enumerated_root_units: [meter_unit, gram_unit])
      end
      let(:unit) do
        Unit.new(
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
        parsed = Unit.from_xml(expected_xml)

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
        parsed = Unit.from_xml(xml)
        regenerated_xml = parsed.to_xml

        expect(regenerated_xml).to be_xml_equivalent_to(expected_xml)
      end
    end

    context "when mixing different namespaces" do
      let(:math) { MathContent.new(value: "x+y") }
      let(:unit_symbol) { UnitSymbol.new(type: "MathML", math: math) }
      let(:unit_with_math) do
        UnitWithMath.new(id: "U_m.kg-2", unit_symbol: unit_symbol)
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

      it "declares xmlns on elements when namespace changes" do
        xml = unit_with_math.to_xml

        # Should have units namespace on Unit
        expect(xml).to include('xmlns="https://schema.example.org/units/1.0"')
        # Should have MathML namespace on math element
        expect(xml).to include('xmlns="http://www.w3.org/1998/Math/MathML"')
      end

      it "does not repeat xmlns on UnitSymbol (same namespace as parent)" do
        xml = unit_with_math.to_xml

        # UnitSymbol should NOT have xmlns because it inherits from Unit
        expect(xml).not_to match(/<UnitSymbol[^>]*xmlns="https:\/\/schema\.example\.org\/units\/1\.0"/)
      end

      it "round-trips XML with mixed namespaces" do
        xml = unit_with_math.to_xml
        parsed = UnitWithMath.from_xml(xml)

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
