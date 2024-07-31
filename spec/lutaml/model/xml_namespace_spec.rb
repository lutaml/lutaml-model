# spec/lutaml/model/xml_adapter_spec.rb
require "spec_helper"
require "lutaml/model/xml_adapter/nokogiri_adapter"
require "lutaml/model/xml_adapter/ox_adapter"
require "lutaml/model/xml_adapter/oga_adapter"
require "lutaml/model"

class SampleNamespacedModel < Lutaml::Model::Serializable
  attribute :id, Lutaml::Model::Type::String
  attribute :lang, Lutaml::Model::Type::String
  attribute :name, Lutaml::Model::Type::String, default: -> { "Anonymous" }
  attribute :age, Lutaml::Model::Type::Integer, default: -> { 18 }

  xml do
    root "SampleNamespacedModel"
    namespace "http://example.com/foo", "foo"

    map_attribute "id", to: :id
    map_attribute "lang", to: :lang,
                          prefix: "xml",
                          namespace: "http://example.com/xml"

    map_element "Name", to: :name, prefix: "bar", namespace: "http://example.com/bar"
    map_element "Age", to: :age, prefix: "baz", namespace: "http://example.com/baz"
  end
end

class NamespaceNill < Lutaml::Model::Serializable
  attribute :namespace_model, SampleNamespacedModel

  xml do
    map_element "SampleNamespacedModel", to: :namespace_model,
                                         namespace: nil,
                                         prefix: nil
  end
end

RSpec.shared_examples "an XML namespace parser" do |adapter_class|
  around do |example|
    old_adapter = Lutaml::Model::Config.xml_adapter
    Lutaml::Model::Config.xml_adapter = adapter_class

    example.run
  ensure
    Lutaml::Model::Config.xml_adapter = old_adapter
  end

  let(:attributes) { { name: "John Doe", age: 30 } }
  let(:model) { SampleNamespacedModel.new(attributes) }

  it "serializes to XML" do
    expected_xml = <<~XML
      <foo:SampleNamespacedModel>
        <bar:Name>John Doe</bar:Name>
        <baz:Age>30</baz:Age>
      </foo:SampleNamespacedModel>
    XML

    doc = adapter_class.parse(expected_xml)
    xml = doc.to_xml
    expect(xml).to be_equivalent_to(expected_xml)
  end

  it "deserializes from XML" do
    xml = <<~XML
      <foo:SampleNamespacedModel>
        <bar:Name>John Doe</bar:Name>
        <baz:Age>30</baz:Age>
      </foo:SampleNamespacedModel>
    XML

    doc = adapter_class.parse(xml)
    new_model = SampleNamespacedModel.new(doc.root.children.to_h do |child|
                                            [
                                              child.unprefixed_name.downcase.to_sym, child.text
                                            ]
                                          end)
    expect(new_model.name).to eq("John Doe")
    expect(new_model.age).to eq(30)
  end

  describe "round-trips from and to XML" do
    it "round-trips if namespace is set" do
      xml = <<~XML
        <foo:SampleNamespacedModel xml:lang="en" xmlns:foo="http://example.com/foo" xmlns:bar="http://example.com/bar" xmlns:baz="http://example.com/baz">
          <bar:Name>John Doe</bar:Name>
          <baz:Age>30</baz:Age>
        </foo:SampleNamespacedModel>
      XML

      doc = SampleNamespacedModel.from_xml(xml)
      generated_xml = doc.to_xml
      expect(generated_xml).to be_equivalent_to(xml)
    end

    it "round-trips if namespace is set to nil in parent" do
      xml = <<~XML
        <NamespaceNill xmlns:foo="http://example.com/foo" xmlns:bar="http://example.com/bar" xmlns:baz="http://example.com/baz">
          <SampleNamespacedModel xml:lang="en">
            <bar:Name>John Doe</bar:Name>
            <baz:Age>30</baz:Age>
          </SampleNamespacedModel>
        </NamespaceNill>
      XML

      doc = NamespaceNill.from_xml(xml)
      generated_xml = doc.to_xml
      expect(generated_xml).to be_equivalent_to(xml)
    end
  end
end

RSpec.describe Lutaml::Model::XmlAdapter::NokogiriDocument do
  it_behaves_like "an XML namespace parser", described_class
end

RSpec.describe Lutaml::Model::XmlAdapter::OxDocument do
  it_behaves_like "an XML namespace parser", described_class
end

RSpec.xdescribe Lutaml::Model::XmlAdapter::OgaDocument do
  it_behaves_like "an XML namespace parser", described_class
end
