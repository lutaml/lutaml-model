require "spec_helper"
require "lutaml/model/xml/nokogiri_adapter"
require "lutaml/model/xml/ox_adapter"
require "lutaml/model/xml/oga_adapter"
require_relative "../../fixtures/sample_model"

module XmlAdapterSpec
  class Mstyle < Lutaml::Model::Serializable
    attribute :displaystyle, :string, default: -> { "true" }
    attribute :color, :string
    attribute :finish, :string, default: -> { "yes" }

    xml do
      root "mstyle"

      map_attribute :displaystyle, to: :displaystyle, render_default: true
    end
  end

  class Maths < Lutaml::Model::Serializable
    attribute :display, :string, default: -> { "block" }
    attribute :style, Mstyle, default: -> { Mstyle.new }

    xml do
      root "math"

      map_attribute :display, to: :display
      map_attribute "color", to: :color, delegate: :style
      map_attribute "finish", to: :finish, delegate: :style,
                              render_default: true
      map_element :mstyle, to: :style, render_default: true
    end
  end
end

RSpec.describe "XmlAdapter" do
  shared_examples "an XML adapter" do |adapter_class|
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

    context "with default value" do
      it "set display attribute correctly, other attributes default" do
        xml = "<math display='true'></math>"

        parsed = XmlAdapterSpec::Maths.from_xml(xml)
        expect(parsed.display).to eq("true")
        expect(parsed.style.class).to eq(XmlAdapterSpec::Mstyle)
        expect(parsed.style.displaystyle).to eq("true")
      end

      it "set style attribute correctly, other attributes default" do
        xml = "<math> <mstyle displaystyle='false'>  </mstyle> </math>"

        parsed = XmlAdapterSpec::Maths.from_xml(xml)
        expect(parsed.display).to eq("block")
        expect(parsed.style.class).to eq(XmlAdapterSpec::Mstyle)
        expect(parsed.style.displaystyle).to eq("false")
      end

      it "sets attributes default values" do
        xml = "<math> </math>"

        parsed = XmlAdapterSpec::Maths.from_xml(xml)
        expect(parsed.display).to eq("block")
        expect(parsed.style.class).to eq(XmlAdapterSpec::Mstyle)
        expect(parsed.style.displaystyle).to eq("true")
      end

      it "delegate attributes with value" do
        xml = "<math color='blue' finish='no'></math>"

        parsed = XmlAdapterSpec::Maths.from_xml(xml)
        expect(parsed.style.color).to eq("blue")
        expect(parsed.style.finish).to eq("no")
        expect(parsed.style.displaystyle).to eq("true")
      end

      it "delegate attributes with one value" do
        xml = "<math color='blue'></math>"

        parsed = XmlAdapterSpec::Maths.from_xml(xml)
        expect(parsed.style.color).to eq("blue")
        expect(parsed.style.finish).to eq("yes")
        expect(parsed.style.displaystyle).to eq("true")
      end

      it "delegate attributes with no value" do
        xml = "<math></math>"

        parsed = XmlAdapterSpec::Maths.from_xml(xml)
        expect(parsed.style.color).to be_nil
        expect(parsed.style.finish).to eq("yes")
        expect(parsed.style.displaystyle).to eq("true")
      end

      context "when round-trips" do
        let(:parsed) do
          XmlAdapterSpec::Maths.from_xml(xml)
        end

        let(:xml) do
          "<math display='true'></math>"
        end

        let(:expected_xml) do
          <<~XML
            <math display="true" finish="yes">
              <mstyle displaystyle="true"/>
            </math>
          XML
        end

        it "add default values" do
          expect(parsed.to_xml.strip).to be_equivalent_to(expected_xml.strip)
        end
      end
    end

    context "when xml has `lang` attribute" do
      before do
        title_class = Class.new(Lutaml::Model::Serializable) do
          attribute :lang, :string
          attribute :content, :string

          xml do
            root "title"

            map_attribute "lang", to: :lang
            map_content to: :content
          end
        end

        stub_const("Title", title_class)
      end

      let(:xml_input) { "<title lang='en'>Title</title>" }
      let(:parsed) { Title.from_xml(xml_input) }

      it { expect(parsed.lang).to eq("en") }
      it { expect(parsed.content).to eq("Title") }
    end

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

  describe Lutaml::Model::Xml::NokogiriAdapter do
    it_behaves_like "an XML adapter", described_class
  end

  describe Lutaml::Model::Xml::OxAdapter do
    it_behaves_like "an XML adapter", described_class
  end

  describe Lutaml::Model::Xml::OgaAdapter do
    it_behaves_like "an XML adapter", described_class
  end
end
