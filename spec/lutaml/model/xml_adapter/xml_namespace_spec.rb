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

        map_attribute "id", to: :id, namespace: "http://www.omg.org/spec/XMI/20131001", prefix: "xmi"
        map_attribute "type", to: :type, namespace: "http://www.omg.org/spec/XMI/20131001", prefix: "xmi"
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

    # Models for testing advanced namespace features (ceramic example)
    class CeramicIdentifier < Lutaml::Model::Serializable
      attribute :name, :string

      xml do
        root "identifier"
        map_content to: :name
        namespace "http://example.com/identifier"
      end
    end

    class CeramicSiteUrl < Lutaml::Model::Serializable
      attribute :url, :string

      xml do
        root "website"
        namespace "http://example.com/url", "s"
        map_content to: :url
      end
    end

    class CeramicPotter < Lutaml::Model::Serializable
      attribute :name, :string

      xml do
        root "potter"
        namespace "http://example.com/potter"
        map_element "name", to: :name
      end
    end

    class CeramicLocation < Lutaml::Model::Serializable
      attribute :address, :string
      attribute :city, :string
      attribute :country, :string

      xml do
        root "location"
        namespace "http://example.com/production"
        map_element "address", to: :address
        map_element "city", to: :city
        map_element "country", to: :country
      end
    end

    class CeramicProductionSite < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :glazes_produced, :string, collection: true
      attribute :location, CeramicLocation
      attribute :website, CeramicSiteUrl
      attribute :established_at, :string

      xml do
        root "production_site"
        namespace "http://example.com/production"
        map_element "name", to: :name
        map_element "glazes_produced", to: :glazes_produced
        map_element "location", to: :location
        map_element "established_at", to: :established_at, namespace: "http://example.com/url"
        map_element "website", to: :website, prefix: "s"
      end
    end

    class CeramicComposition < Lutaml::Model::Serializable
      attribute :name, :string

      xml do
        root "composition"
        map_content to: :name
        namespace "http://example.com/ceramic"
      end
    end

    class CeramicCategory < Lutaml::Model::Serializable
      attribute :name, :string

      xml do
        root "category"
        map_content to: :name
        namespace "http://example.com/ceramic"
      end
    end

    class CeramicModel < Lutaml::Model::Serializable
      attribute :type, :string
      attribute :composition_name, :string
      attribute :id_name, :string
      attribute :glaze, :string
      attribute :category_name, :string
      attribute :production_site, CeramicProductionSite
      attribute :potter, CeramicPotter

      xml do
        root "ceramic"
        namespace "http://example.com/ceramic"

        map_attribute "type", to: :type
        map_attribute "composition", to: :composition_name
        map_attribute "id", to: :id_name, prefix: "c", namespace: "http://example.com/identifier"
        map_element "glaze", to: :glaze
        map_element "category", to: :category_name
        map_element "production_site", to: :production_site
        map_element "potter", to: :potter, prefix: "p"
      end
    end
  end

  shared_examples "XML serialization with namespace" do |model_class, xml_string|
    it "serializes to XML" do
      model = model_class.new(name: "Test Name")
      expect(model.to_xml).to be_equivalent_to(xml_string)
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
        expect(model.to_xml).to be_equivalent_to(xml)
      end

      it "deserializes from XML" do
        new_model = SamplePrefixedNamespacedModel.from_xml(xml)
        expect(new_model.name).to eq("John Doe")
        expect(new_model.age).to eq(30)
      end

      it "round-trips if namespace is set" do
        doc = SamplePrefixedNamespacedModel.from_xml(xml_with_lang)
        generated_xml = doc.to_xml
        expect(generated_xml).to be_equivalent_to(xml_with_lang)
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
        expect(generated_xml).to be_equivalent_to(xml)
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

        expect(model.to_xml).to be_equivalent_to(expected_xml)
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
        expect(generated_xml).to be_equivalent_to(xml)
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
        expect(generated_xml).to be_equivalent_to(xml)
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

          expect(output_xml).to be_equivalent_to(xml_input)
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

          expect(owned_end.to_xml).to be_equivalent_to(xml_input)
        end

        it "round-trips XML" do
          owned_end = OwnedEnd.from_xml(xml_input)
          output_xml = owned_end.to_xml

          expect(output_xml).to be_equivalent_to(xml_input)
        end
      end
    end

    context "when nested elements share the same namespace" do
      let(:unit_system) { UnitSystem.new(name: "SI", type: "SI_derived") }
      let(:unit_name) { UnitName.new(value: "meter") }
      let(:meter_unit) { EnumeratedRootUnit.new(unit: "meter") }
      let(:gram_unit) { EnumeratedRootUnit.new(unit: "gram", prefix: "k") }
      let(:root_units) { RootUnits.new(enumerated_root_units: [meter_unit, gram_unit]) }
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
        expect(xml).to be_equivalent_to(expected_xml)
      end

      it "does not repeat xmlns on child elements with same namespace" do
        xml = unit.to_xml

        # Count xmlns declarations for the units namespace
        xmlns_count = xml.scan('xmlns="https://schema.example.org/units/1.0"').size

        expect(xmlns_count).to eq(1), "Expected exactly 1 xmlns declaration, found #{xmlns_count}"
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

        expect(regenerated_xml).to be_equivalent_to(expected_xml)
      end
    end

    context "when mixing different namespaces" do
      let(:math) { MathContent.new(value: "x+y") }
      let(:unit_symbol) { UnitSymbol.new(type: "MathML", math: math) }
      let(:unit_with_math) { UnitWithMath.new(id: "U_m.kg-2", unit_symbol: unit_symbol) }

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
        expect(xml).to be_equivalent_to(expected_xml)
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
        expect(regenerated_xml).to be_equivalent_to(expected_xml)
      end
    end

    context "when attributes use custom namespace and prefix" do
      let(:ceramic) do
        CeramicModel.new(
          type: "Fine Porcelain",
          composition_name: "Porcelain",
          id_name: "1234",
          glaze: "Celadon",
          category_name: "Ornamental",
        )
      end

      let(:expected_xml_snippet) do
        # Just the opening tag with attributes
        '<ceramic xmlns="http://example.com/ceramic" xmlns:c="http://example.com/identifier" type="Fine Porcelain" composition="Porcelain" c:id="1234">'
      end

      it "serializes attributes with namespace prefix correctly" do
        xml = ceramic.to_xml
        
        # Check that the prefixed attribute is present
        expect(xml).to include('c:id="1234"')
        
        # Check that the namespace declaration is present
        expect(xml).to include('xmlns:c="http://example.com/identifier"')
      end

      it "serializes regular attributes without prefix" do
        xml = ceramic.to_xml
        
        # Regular attributes should not have prefixes
        expect(xml).to include('type="Fine Porcelain"')
        expect(xml).to include('composition="Porcelain"')
        expect(xml).not_to match(/\w+:type=/)
        expect(xml).not_to match(/\w+:composition=/)
      end

      it "deserializes attributes with namespace prefix correctly" do
        xml = ceramic.to_xml
        parsed = CeramicModel.from_xml(xml)
        
        expect(parsed.id_name).to eq("1234")
        expect(parsed.type).to eq("Fine Porcelain")
        expect(parsed.composition_name).to eq("Porcelain")
      end
    end

    context "when child element declares new default namespace" do
      let(:location) { CeramicLocation.new(address: "15 Rue du Temple", city: "Limoges", country: "France") }
      let(:production_site) do
        CeramicProductionSite.new(
          name: "Bernardaud Factory",
          glazes_produced: ["Celadon", "Crystalline"],
          location: location,
          established_at: "2010",
        )
      end
      let(:ceramic) do
        CeramicModel.new(
          type: "Fine Porcelain",
          glaze: "Celadon",
          production_site: production_site,
          composition_name: "Porcelain",
          id_name: "1234",
          category_name: "Ornamental",
        )
      end

      it "declares namespace on child element when switching from parent namespace" do
        xml = ceramic.to_xml
        
        # production_site should declare its own namespace since it's different from ceramic
        expect(xml).to match(/<production_site[^>]*xmlns="http:\/\/example\.com\/production"/)
      end

      it "does not repeat parent namespace declaration on child" do
        xml = ceramic.to_xml
        
        # ceramic namespace should only appear on ceramic element, not on production_site
        ceramic_ns_count = xml.scan('xmlns="http://example.com/ceramic"').size
        expect(ceramic_ns_count).to eq(1)
      end

      it "deserializes child elements with different namespaces correctly" do
        xml = ceramic.to_xml
        parsed = CeramicModel.from_xml(xml)
        
        expect(parsed.production_site.name).to eq("Bernardaud Factory")
        expect(parsed.production_site.glazes_produced).to eq(["Celadon", "Crystalline"])
        expect(parsed.production_site.location.city).to eq("Limoges")
      end
    end

    context "when nested elements switch namespaces multiple times" do
      let(:site_url) { CeramicSiteUrl.new(url: "http://www.bernardaud.com") }
      let(:location) { CeramicLocation.new(address: "15 Rue du Temple", city: "Limoges", country: "France") }
      let(:production_site) do
        CeramicProductionSite.new(
          name: "Bernardaud Factory",
          location: location,
          established_at: "2010",
          website: site_url,
        )
      end

      it "declares namespace on deeply nested element when switching" do
        xml = production_site.to_xml
        
        # established_at switches to url namespace within production namespace
        expect(xml).to match(/<established_at[^>]*xmlns="http:\/\/example\.com\/url"/)
      end

      it "uses prefix for nested element with different namespace" do
        xml = production_site.to_xml
        
        # website should use s: prefix
        expect(xml).to match(/<s:website[^>]*>/)
        expect(xml).to include('xmlns:s="http://example.com/url"')
      end

      it "does not add namespace declaration to elements sharing parent namespace" do
        xml = production_site.to_xml
        
        # location shares production namespace, should not redeclare it
        expect(xml).not_to match(/<location[^>]*xmlns=/)
      end

      it "deserializes nested namespace switches correctly" do
        xml = production_site.to_xml
        parsed = CeramicProductionSite.from_xml(xml)
        
        expect(parsed.established_at).to eq("2010")
        expect(parsed.website.url).to eq("http://www.bernardaud.com")
        expect(parsed.location.address).to eq("15 Rue du Temple")
      end
    end

    context "when round-tripping complex multi-namespace XML" do
      let(:location) { CeramicLocation.new(address: "15 Rue du Temple", city: "Limoges", country: "France") }
      let(:site_url) { CeramicSiteUrl.new(url: "http://www.bernardaud.com") }
      let(:production_site) do
        CeramicProductionSite.new(
          name: "Bernardaud Factory",
          glazes_produced: ["Celadon", "Crystalline"],
          location: location,
          established_at: "2010",
          website: site_url,
        )
      end
      let(:potter) { CeramicPotter.new(name: "Alice Perrin") }
      let(:ceramic) do
        CeramicModel.new(
          type: "Fine Porcelain",
          glaze: "Celadon",
          production_site: production_site,
          potter: potter,
          composition_name: "Porcelain",
          id_name: "1234",
          category_name: "Ornamental",
        )
      end

      it "preserves all data through round-trip" do
        original_xml = ceramic.to_xml
        parsed = CeramicModel.from_xml(original_xml)
        
        expect(parsed.type).to eq("Fine Porcelain")
        expect(parsed.glaze).to eq("Celadon")
        expect(parsed.composition_name).to eq("Porcelain")
        expect(parsed.id_name).to eq("1234")
        expect(parsed.category_name).to eq("Ornamental")
        expect(parsed.potter.name).to eq("Alice Perrin")
        expect(parsed.production_site.name).to eq("Bernardaud Factory")
        expect(parsed.production_site.established_at).to eq("2010")
      end

      it "preserves namespace structure through round-trip" do
        original_xml = ceramic.to_xml
        parsed = CeramicModel.from_xml(original_xml)
        regenerated_xml = parsed.to_xml
        
        # Check that key namespace declarations are still present
        expect(regenerated_xml).to include('xmlns="http://example.com/ceramic"')
        expect(regenerated_xml).to include('xmlns:c="http://example.com/identifier"')
        expect(regenerated_xml).to include('xmlns:p="http://example.com/potter"')
        expect(regenerated_xml).to match(/<production_site[^>]*xmlns="http:\/\/example\.com\/production"/)
      end

      it "produces equivalent XML after round-trip" do
        original_xml = ceramic.to_xml
        parsed = CeramicModel.from_xml(original_xml)
        regenerated_xml = parsed.to_xml
        
        expect(regenerated_xml).to be_equivalent_to(original_xml)
      end
    end

    context "with comprehensive multi-namespace example (ceramic)" do
      let(:location) { CeramicLocation.new(address: "15 Rue du Temple", city: "Limoges", country: "France") }
      let(:site_url) { CeramicSiteUrl.new(url: "http://www.bernardaud.com") }
      let(:production_site) do
        CeramicProductionSite.new(
          name: "Bernardaud Factory",
          glazes_produced: ["Celadon", "Crystalline"],
          location: location,
          established_at: "2010",
          website: site_url,
        )
      end
      let(:potter) { CeramicPotter.new(name: "Alice Perrin") }
      let(:ceramic) do
        CeramicModel.new(
          type: "Fine Porcelain",
          glaze: "Celadon",
          production_site: production_site,
          potter: potter,
          composition_name: "Porcelain",
          id_name: "1234",
          category_name: "Ornamental",
        )
      end

      let(:expected_xml) do
        <<~XML
          <ceramic xmlns="http://example.com/ceramic" xmlns:p="http://example.com/potter" xmlns:c="http://example.com/identifier" type="Fine Porcelain" composition="Porcelain" c:id="1234">
            <glaze>Celadon</glaze>
            <category>Ornamental</category>
            <production_site xmlns="http://example.com/production" xmlns:s="http://example.com/url">
              <name>Bernardaud Factory</name>
              <glazes_produced>Celadon</glazes_produced>
              <glazes_produced>Crystalline</glazes_produced>
              <location>
                <address>15 Rue du Temple</address>
                <city>Limoges</city>
                <country>France</country>
              </location>
              <established_at xmlns="http://example.com/url">2010</established_at>
              <s:website>http://www.bernardaud.com</s:website>
            </production_site>
            <p:potter>
              <p:name>Alice Perrin</p:name>
            </p:potter>
          </ceramic>
        XML
      end

      it "serializes complex multi-namespace structure correctly" do
        xml = ceramic.to_xml
        expect(xml).to be_equivalent_to(expected_xml)
      end

      it "includes all namespace declarations on root element" do
        xml = ceramic.to_xml
        
        # Root element should declare ceramic, potter, and identifier namespaces
        expect(xml).to match(/<ceramic[^>]*xmlns="http:\/\/example\.com\/ceramic"/)
        expect(xml).to match(/<ceramic[^>]*xmlns:p="http:\/\/example\.com\/potter"/)
        expect(xml).to match(/<ceramic[^>]*xmlns:c="http:\/\/example\.com\/identifier"/)
      end

      it "handles prefixed attributes correctly" do
        xml = ceramic.to_xml
        
        expect(xml).to include('c:id="1234"')
        expect(xml).to include('type="Fine Porcelain"')
      end

      it "handles elements with same namespace as parent without prefix" do
        xml = ceramic.to_xml
        
        # glaze and category share ceramic namespace, no prefix needed
        expect(xml).to include("<glaze>Celadon</glaze>")
        expect(xml).to include("<category>Ornamental</category>")
      end

      it "handles prefixed elements with different namespaces" do
        xml = ceramic.to_xml
        
        # potter has different namespace and uses prefix
        expect(xml).to match(/<p:potter[^>]*>/)
        expect(xml).to include("<p:name>Alice Perrin</p:name>")
      end

      it "handles child elements switching to new default namespace" do
        xml = ceramic.to_xml
        
        # production_site switches to production namespace
        expect(xml).to match(/<production_site[^>]*xmlns="http:\/\/example\.com\/production"/)
      end

      it "handles nested namespace switching" do
        xml = ceramic.to_xml
        
        # established_at switches to url namespace within production_site
        expect(xml).to match(/<established_at[^>]*xmlns="http:\/\/example\.com\/url"/)
      end

      it "handles elements with same namespace as new parent without redeclaring" do
        xml = ceramic.to_xml
        
        # location shares production namespace with production_site
        expect(xml).not_to match(/<location[^>]*xmlns=/)
      end

      it "deserializes complete structure correctly" do
        xml = ceramic.to_xml
        parsed = CeramicModel.from_xml(xml)
        
        # Check all attributes
        expect(parsed.type).to eq("Fine Porcelain")
        expect(parsed.composition_name).to eq("Porcelain")
        expect(parsed.id_name).to eq("1234")
        expect(parsed.glaze).to eq("Celadon")
        expect(parsed.category_name).to eq("Ornamental")
        
        # Check nested potter
        expect(parsed.potter.name).to eq("Alice Perrin")
        
        # Check nested production_site
        expect(parsed.production_site.name).to eq("Bernardaud Factory")
        expect(parsed.production_site.glazes_produced).to eq(["Celadon", "Crystalline"])
        expect(parsed.production_site.established_at).to eq("2010")
        expect(parsed.production_site.website.url).to eq("http://www.bernardaud.com")
        
        # Check deeply nested location
        expect(parsed.production_site.location.address).to eq("15 Rue du Temple")
        expect(parsed.production_site.location.city).to eq("Limoges")
        expect(parsed.production_site.location.country).to eq("France")
      end

      it "round-trips complete structure preserving all namespaces" do
        original_xml = ceramic.to_xml
        parsed = CeramicModel.from_xml(original_xml)
        regenerated_xml = parsed.to_xml
        
        expect(regenerated_xml).to be_equivalent_to(expected_xml)
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
