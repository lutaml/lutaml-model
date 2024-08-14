require "spec_helper"
require "lutaml/model/xml_adapter/nokogiri_adapter"
require "lutaml/model/xml_adapter/ox_adapter"
require "lutaml/model/xml_adapter/oga_adapter"
require_relative "../../fixtures/sample_model"

class MixedContent < Lutaml::Model::Serializable
  attribute :id, Lutaml::Model::Type::String
  attribute :bold, Lutaml::Model::Type::String
  attribute :italic, Lutaml::Model::Type::String, collection: true
  attribute :underline, Lutaml::Model::Type::String
  attribute :sample_model, SampleModel
  attribute :content, Lutaml::Model::Type::String

  xml do
    root "MixedContent"

    map_content to: :content

    map_attribute :id, to: :id

    map_element :bold, to: :bold
    map_element :italic, to: :italic
    map_element :underline, to: :underline
    map_element "SampleModel", to: :sample_model
  end
end

class WithoutMixedContent < Lutaml::Model::Serializable
  attribute :id, Lutaml::Model::Type::String
  attribute :text, Lutaml::Model::Type::String
  attribute :mixed_content, MixedContent
  attribute :p, Lutaml::Model::Type::String

  xml do
    root "WithoutMixedContent"

    map_content to: :text

    map_attribute :id, to: :id

    map_element "MixedContent", to: :mixed_content, mixed: true
    map_element :p, to: :p
  end
end

RSpec.shared_examples "an XML adapter" do |adapter_class|
  around do |example|
    old_adapter = Lutaml::Model::Config.xml_adapter
    Lutaml::Model::Config.xml_adapter = adapter_class

    example.run
  ensure
    Lutaml::Model::Config.xml_adapter = old_adapter
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

  context "when mixed: true is set for tags" do
    describe "deserializes from XML" do
      let(:xml) do
        <<~XML
          <WithoutMixedContent id="123">
            Some text before mixed content

            <MixedContent id="456">
              This is some <bold>bold</bold> and some <italic>italic</italic> text
              and some <underline>underlined</underline> text as well
              and <italic>some more italic</italic> text.
              <SampleModel>
                <Name>John Doe</Name>
                <Age>30</Age>
              </SampleModel>
              Text after nested tag
            </MixedContent>
          </WithoutMixedContent>
        XML
      end

      let(:parsed_xml) { WithoutMixedContent.from_xml(xml) }

      it "output correct XML" do
        expect(parsed_xml.to_xml).to be_equivalent_to(xml)
      end
    end

    describe "only attributes without children" do
      let(:xml) do
        <<~XML
          <WithoutMixedContent id="123">
            Some text before mixed content

            <MixedContent id="456"></MixedContent>
          </WithoutMixedContent>
        XML
      end

      let(:parsed_xml) { WithoutMixedContent.from_xml(xml) }

      it "output correct XML" do
        expect(parsed_xml.to_xml).to be_equivalent_to(xml)
      end
    end
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
