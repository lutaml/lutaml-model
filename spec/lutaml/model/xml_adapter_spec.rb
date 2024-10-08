require "spec_helper"
require "lutaml/model/xml_adapter/nokogiri_adapter"
require "lutaml/model/xml_adapter/ox_adapter"
require "lutaml/model/xml_adapter/oga_adapter"
require_relative "../../fixtures/sample_model"

RSpec.shared_examples "an XML adapter" do |adapter_class|
  around do |example|
    old_adapter = Lutaml::Model::Config.xml_adapter
    Lutaml::Model::Config.xml_adapter = adapter_class

    example.run
  ensure
    Lutaml::Model::Config.xml_adapter = old_adapter
  end

  before do
    # Ensure BigDecimal is loaded because it is being used in sample model
    require "bigdecimal"
  end

  let(:attributes) { { name: "John Doe", age: 30 } }
  let(:model) { SampleModel.new(attributes) }

  it "serializes to XML" do
    expected_xml = <<~XML
      <SampleModel>
        <Name>John Doe</Name>
        <Age>30</Age>
      </SampleModel>
    XML

    doc = adapter_class.parse(expected_xml)
    xml = doc.to_xml
    expect(xml).to be_equivalent_to(expected_xml)
  end

  it "serializes to XML with only content" do
    expected_xml = <<~XML
      <Tag>
        Bug
      </Tag>
    XML

    doc = SampleModelTag.from_xml(expected_xml)
    xml = doc.to_xml
    expect(xml).to be_equivalent_to(expected_xml)
  end

  it "deserializes from XML" do
    xml = <<~XML
      <SampleModel>
        <Name>John Doe</Name>
        <Age>30</Age>
      </SampleModel>
    XML

    doc = adapter_class.parse(xml)
    new_model = SampleModel.new(doc.root.children.to_h do |child|
      [child.name.downcase.to_sym, child.text]
    end)
    expect(new_model.name).to eq("John Doe")
    expect(new_model.age).to eq(30)
  end
end

RSpec.describe Lutaml::Model::XmlAdapter::NokogiriAdapter do
  it_behaves_like "an XML adapter", described_class
end

RSpec.describe Lutaml::Model::XmlAdapter::OxAdapter do
  it_behaves_like "an XML adapter", described_class
end

RSpec.xdescribe Lutaml::Model::XmlAdapter::OgaAdapter do
  it_behaves_like "an XML adapter", described_class
end
