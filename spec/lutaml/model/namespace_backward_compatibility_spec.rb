require "spec_helper"
require_relative "../../support/xml_mapping_namespaces"

# This spec verifies that the XmlNamespace class-based API works correctly
# String-based namespaces are deprecated and no longer fully supported
RSpec.describe "XmlNamespace Class API" do
  describe "xml-block level namespace" do
    context "with prefixed namespace" do
      let(:model_class) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string

          xml do
            element "test"
            namespace TestNamespace
            map_element "name", to: :name
          end
        end
      end

      it "produces correct XML with namespace" do
        instance = model_class.new(name: "Test Name")
        xml = instance.to_xml

        expect(xml).to include('xmlns')
        expect(xml).to include('http://example.com/test')
      end

      it "parses XML with namespace correctly" do
        xml = '<ex:test xmlns:ex="http://example.com/test"><ex:name>Test Name</ex:name></ex:test>'
        parsed = model_class.from_xml(xml)

        expect(parsed.name).to eq("Test Name")
      end
    end
  end

  describe "programmatic namespace method" do
    it "mapping.namespace() with XmlNamespace class works" do
      mapping = Lutaml::Model::Xml::Mapping.new
      mapping.root("element")
      mapping.namespace(TestNamespace)

      expect(mapping.namespace_uri).to eq("http://example.com/test")
      expect(mapping.namespace_prefix).to eq("test")
    end
  end
end
