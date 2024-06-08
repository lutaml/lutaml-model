# spec/lutaml/model/xml_adapter_spec.rb
require "spec_helper"
require "lutaml/model/xml_adapter/nokogiri_adapter"
require "lutaml/model/xml_adapter/ox_adapter"
require "lutaml/model/xml_adapter/oga_adapter"
require_relative "../fixtures/sample_model"

RSpec.shared_examples "an XML adapter" do |adapter_class|
  let(:attributes) { { name: "John Doe", age: 30 } }
  let(:model) { SampleModel.new(attributes) }

  it "serializes to XML" do
    expected_xml = Nokogiri::XML::Builder.new do |xml|
      xml.SampleModel {
        xml.Name "John Doe"
        xml.Age "30"
      }
    end.to_xml

    doc = adapter_class.new(Lutaml::Model::XmlAdapter::NokogiriElement.new(Nokogiri::XML(expected_xml).root))
    xml = doc.to_xml
    expect(Nokogiri::XML(xml).to_s).to eq(Nokogiri::XML(expected_xml).to_s)
  end

  it "deserializes from XML" do
    xml = Nokogiri::XML::Builder.new do |xml|
      xml.SampleModel {
        xml.Name "John Doe"
        xml.Age "30"
      }
    end.to_xml

    doc = adapter_class.parse(xml)
    new_model = SampleModel.new(doc.root.children.map { |child| [child.name.downcase.to_sym, child.text] }.to_h)
    expect(new_model.name).to eq("John Doe")
    expect(new_model.age).to eq(30)
  end
end

RSpec.describe Lutaml::Model::XmlAdapter::NokogiriDocument do
  it_behaves_like "an XML adapter", described_class
end

RSpec.describe Lutaml::Model::XmlAdapter::OxDocument do
  it_behaves_like "an XML adapter", described_class
end

RSpec.describe Lutaml::Model::XmlAdapter::OgaDocument do
  it_behaves_like "an XML adapter", described_class
end
