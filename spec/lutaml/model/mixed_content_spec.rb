# spec/lutaml/model/mixed_content_spec.rb

require "spec_helper"
require "lutaml/model"
require "lutaml/model/xml_adapter/nokogiri_adapter"
require "lutaml/model/xml_adapter/ox_adapter"
require "lutaml/model/xml_adapter/oga_adapter"
require_relative "../../fixtures/sample_model"

module MixedContentSpec
  class PlanetaryBody < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :distance_from_earth, :integer
    xml do
      root "PlanetaryBody"
      map_element "Name", to: :name
      map_element "DistanceFromEarth", to: :distance_from_earth
    end
  end

  class RootMixedContent < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :bold, :string, collection: true
    attribute :italic, :string, collection: true
    attribute :underline, :string
    attribute :content, :string

    xml do
      root "RootMixedContent", mixed: true
      map_attribute :id, to: :id
      map_element :bold, to: :bold
      map_element :italic, to: :italic
      map_element :underline, to: :underline
      map_content to: :content
    end
  end

  class RootMixedContentWithModel < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :bold, :string, collection: true
    attribute :italic, :string, collection: true
    attribute :underline, :string
    attribute :planetary_body, PlanetaryBody
    attribute :content, :string

    xml do
      root "RootMixedContentWithModel", mixed: true
      map_content to: :content
      map_attribute :id, to: :id
      map_element :bold, to: :bold
      map_element :italic, to: :italic
      map_element :underline, to: :underline
      map_element "PlanetaryBody", to: :planetary_body
    end
  end

  class RootMixedContentNested < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :text, :string
    attribute :content, RootMixedContent
    attribute :sup, :string, collection: true
    attribute :sub, :string, collection: true

    xml do
      root "RootMixedContentNested", mixed: true
      map_content to: :text
      map_attribute :id, to: :id
      map_element :sup, to: :sup
      map_element :sub, to: :sub
      map_element "MixedContent", to: :content
    end
  end

  class RootMixedContentNestedWithModel < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :text, :string
    attribute :content, RootMixedContentWithModel
    attribute :sup, :string, collection: true
    attribute :sub, :string, collection: true

    xml do
      root "RootMixedContentNestedWithModel", mixed: true

      map_content to: :text

      map_attribute :id, to: :id

      map_element :sup, to: :sup
      map_element :sub, to: :sub
      map_element "MixedContentWithModel", to: :content
    end
  end
end

RSpec.describe "Mixed content" do
  shared_examples "mixed content behavior" do |adapter_class|
    around do |example|
      old_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_class
      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = old_adapter
    end

    context "when mixed: true is set at root" do
      let(:xml) do
        <<~XML
          <RootMixedContent id="123">
            The Earth's Moon rings like a <bold>bell</bold> when struck by
            meteroids. Distanced from the Earth by <italic>384,400 km</italic>,
            its surface is covered in <underline>craters</underline>.
            Ain't that <bold>cool</bold>?
          </RootMixedContent>
        XML
      end

      it "deserializes and serializes mixed content correctly" do
        parsed = MixedContentSpec::RootMixedContent.from_xml(xml)

        expected_content = [
          "\n  The Earth's Moon rings like a ",
          " when struck by\n  meteroids. Distanced from the Earth by ",
          ",\n  its surface is covered in ",
          ".\n  Ain't that ",
          "?\n",
        ]

        expect(parsed.id).to eq("123")
        expect(parsed.bold).to eq(["bell", "cool"])
        expect(parsed.italic).to eq(["384,400 km"])
        expect(parsed.underline).to eq("craters")

        parsed.content.each_with_index do |content, index|
          expected_output = expected_content[index]

          # due to the difference in capturing newlines in ox and nokogiri adapters
          if adapter_class == Lutaml::Model::XmlAdapter::OxAdapter
            expected_output = expected_output.gsub(/\n\s*/, " ")
          end

          expect(content).to eq(expected_output)
        end

        serialized = parsed.to_xml
        expect(serialized).to be_equivalent_to(xml)
      end
    end

    context "when mixed: true is set at root with nested model" do
      let(:xml) do
        <<~XML
          <RootMixedContentWithModel id="123">
            The Earth's Moon rings like a <bold>bell</bold> when struck by
            meteroids. Distanced from the Earth by <italic>384,400 km</italic>,
            its surface is covered in <underline>craters</underline>.
            Ain't that <bold>cool</bold>?
            <PlanetaryBody>
              <Name>Moon</Name>
              <DistanceFromEarth>384400</DistanceFromEarth>
            </PlanetaryBody>
            NOTE: The above model content is to be formatted as a table.
          </RootMixedContentWithModel>
        XML
      end

      it "deserializes and serializes mixed content correctly" do
        parsed = MixedContentSpec::RootMixedContentWithModel.from_xml(xml)

        expected_content = [
          "\n  The Earth's Moon rings like a ",
          " when struck by\n  meteroids. Distanced from the Earth by ",
          ",\n  its surface is covered in ",
          ".\n  Ain't that ",
          "?\n  ",
          "\n  NOTE: The above model content is to be formatted as a table.\n"
        ]

        expect(parsed.id).to eq("123")
        expect(parsed.bold).to eq(["bell", "cool"])
        expect(parsed.italic).to eq(["384,400 km"])
        expect(parsed.underline).to eq("craters")

        parsed.content.each_with_index do |content, index|
          expected_output = expected_content[index]

          # due to the difference in capturing newlines in ox and nokogiri adapters
          if adapter_class == Lutaml::Model::XmlAdapter::OxAdapter
            expected_output = expected_output.gsub(/\n\s*/, " ")
          end

          expect(content).to eq(expected_output)
        end

        expect(parsed.planetary_body.name).to eq("Moon")
        expect(parsed.planetary_body.distance_from_earth).to eq(384400)

        serialized = parsed.to_xml
        expect(serialized).to be_equivalent_to(xml)
      end
    end

    context "when mixed: true is set for nested content" do
      let(:xml) do
        <<~XML
          <RootMixedContentNested id="outer123">
            The following text is about the Moon.
            <MixedContent id="inner456">
              The Earth's Moon rings like a <bold>bell</bold> when struck by
              meteroids. Distanced from the Earth by <italic>384,400 km</italic>,
              its surface is covered in <underline>craters</underline>.
              Ain't that <bold>cool</bold>?
            </MixedContent>
            <sup>1</sup>: The Moon is not a planet.
            <sup>2</sup>: The Moon's atmosphere is mainly composed of helium in the form of He<sub>2</sub>.
          </RootMixedContentNested>
        XML
      end

      it "deserializes and serializes mixed content correctly" do
        parsed = MixedContentSpec::RootMixedContentNested.from_xml(xml)

        expected_content = [
          "\n    The Earth's Moon rings like a ",
          " when struck by\n    meteroids. Distanced from the Earth by ",
          ",\n    its surface is covered in ",
          ".\n    Ain't that ",
          "?\n  ",
        ]

        expect(parsed.id).to eq("outer123")
        expect(parsed.sup).to eq(["1", "2"])
        expect(parsed.sub).to eq(["2"])
        expect(parsed.content.id).to eq("inner456")
        expect(parsed.content.bold).to eq(["bell", "cool"])
        expect(parsed.content.italic).to eq(["384,400 km"])
        expect(parsed.content.underline).to eq("craters")

        parsed.content.content.each_with_index do |content, index|
          expected_output = expected_content[index]

          # due to the difference in capturing newlines in ox and nokogiri adapters
          if adapter_class == Lutaml::Model::XmlAdapter::OxAdapter
            expected_output = expected_output.gsub(/\n\s*/, " ")
          end

          expect(content).to eq(expected_output)
        end

        serialized = parsed.to_xml
        expect(serialized).to be_equivalent_to(xml)
      end
    end

    context "when mixed: true is set for nested content with model" do
      let(:xml) do
        <<~XML
          <RootMixedContentNestedWithModel id="outer123">
            The following text is about the Moon.
            <MixedContentWithModel id="inner456">
              The Earth's Moon rings like a <bold>bell</bold> when struck by
              meteroids. Distanced from the Earth by <italic>384,400 km</italic>,
              its surface is covered in <underline>craters</underline>.
              Ain't that <bold>cool</bold>?
              <PlanetaryBody>
                <Name>Moon</Name>
                <DistanceFromEarth>384400</DistanceFromEarth>
              </PlanetaryBody>
              NOTE: The above model content is to be formatted as a table.
            </MixedContentWithModel>
            <sup>1</sup>: The Moon is not a planet.
            <sup>2</sup>: The Moon's atmosphere is mainly composed of helium in the form of He<sub>2</sub>.
          </RootMixedContentNestedWithModel>
        XML
      end

      it "deserializes and serializes mixed content correctly" do
        parsed = MixedContentSpec::RootMixedContentNestedWithModel.from_xml(xml)

        expected_content = [
          "\n    The Earth's Moon rings like a ",
          " when struck by\n    meteroids. Distanced from the Earth by ",
          ",\n    its surface is covered in ",
          ".\n    Ain't that ",
          "?\n    ",
          "\n    NOTE: The above model content is to be formatted as a table.\n  ",
        ]

        expect(parsed.id).to eq("outer123")
        expect(parsed.sup).to eq(["1", "2"])
        expect(parsed.sub).to eq(["2"])
        expect(parsed.content.id).to eq("inner456")
        expect(parsed.content.bold).to eq(["bell", "cool"])
        expect(parsed.content.italic).to eq(["384,400 km"])
        expect(parsed.content.underline).to eq("craters")

        parsed.content.content.each_with_index do |content, index|
          expected_output = expected_content[index]

          # due to the difference in capturing newlines in ox and nokogiri adapters
          if adapter_class == Lutaml::Model::XmlAdapter::OxAdapter
            expected_output = expected_output.gsub(/\n\s*/, " ")
          end

          expect(content).to eq(expected_output)
        end

        expect(parsed.content.planetary_body.name).to eq("Moon")
        expect(parsed.content.planetary_body.distance_from_earth).to eq(384400)

        serialized = parsed.to_xml
        expect(serialized).to be_equivalent_to(xml)
      end
    end

    context "when mixed: true is used with map_element" do
      it "raises an error" do
        expect {
          Class.new(Lutaml::Model::Serializable) do
            attribute :id, :string

            xml do
              root "Invalid"
              map_element :id, to: :id, mixed: true
            end
          end
        }.to raise_error(ArgumentError, /unknown keyword: :mixed/)
      end
    end

    context "when mixed: true is used with map_attribute" do
      it "raises an error" do
        expect {
          Class.new(Lutaml::Model::Serializable) do
            attribute :id, :string

            xml do
              root "Invalid"
              map_attribute :id, to: :id, mixed: true
            end
          end
        }.to raise_error(ArgumentError, /unknown keyword: :mixed/)
      end
    end
  end

  describe Lutaml::Model::XmlAdapter::NokogiriAdapter do
    it_behaves_like "mixed content behavior", described_class
  end

  describe Lutaml::Model::XmlAdapter::OxAdapter do
    it_behaves_like "mixed content behavior", described_class
  end

  xdescribe Lutaml::Model::XmlAdapter::OgaAdapter do
    it_behaves_like "mixed content behavior", described_class
  end
end
