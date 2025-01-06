require "spec_helper"
require "lutaml/model"

module SequenceSpec
  class Ceramic < Lutaml::Model::Serializable
    attribute :test, :string

    sequence do
      attribute :name, :string
      attribute :type, :string
      attribute :color, :string

      sequence do
        attribute :origin, :string
        attribute :material, :string

        sequence do
          attribute :pattern, :string
        end
      end

      sequence do
        attribute :usage, :string
        attribute :size, :string
      end
    end

    sequence do
      choice do
        group do
          sequence do
            attribute :style, :string
            attribute :is_handmade, :boolean
          end
        end

        attribute :condition, :string
      end

      choice do
        attribute :designer, :string
        attribute :year_made, :integer
      end

      attribute :price, :string
      attribute :location, :string
    end
  end

  class SequenceWithExplicitMapping < Lutaml::Model::Serializable
    sequence do
      attribute :id, :integer
      attribute :bold, :string
      attribute :italic, :string
    end

    xml do
      root "SequenceWithExplicitMapping"
      map_element :id, to: :id
      map_element :bold, to: :bold
      map_element :italic, to: :italic
    end
  end

  class SequenceWithXmlAttribute < Lutaml::Model::Serializable
    sequence do
      attribute :town, :string
      attribute :country, :string
    end

    attribute :city, :string

    xml do
      root "SequenceWithXmlAttribute"
      map_element :town, to: :town
      map_attribute :city, to: :city
      map_content to: :country
    end
  end
end

RSpec.describe "Sequence" do
  context "with default mappings" do
    let(:mapper) { SequenceSpec::Ceramic }

    let(:xml) do
      <<~XML
        <Ceramic>
          <name>Vase</name>
          <type>Decorative</type>
          <color>Blue</color>
          <origin>China</origin>
          <material>Porcelain</material>
          <pattern>Floral</pattern>
          <usage>Indoor</usage>
          <size>Medium</size>
          <condition>New</condition>
          <designer>John Doe</designer>
          <price>100</price>
          <location>Gallery</location>
        </Ceramic>
      XML
    end

    let(:xml_with_alternate_selection) do
      <<~XML
        <Ceramic>
          <name>Vase</name>
          <type>Decorative</type>
          <color>Blue</color>
          <origin>China</origin>
          <material>Porcelain</material>
          <pattern>Floral</pattern>
          <usage>Indoor</usage>
          <size>Medium</size>
          <style>Modern</style>
          <is_handmade>false</is_handmade>
          <year_made>2020</year_made>
          <price>100</price>
          <location>Gallery</location>
        </Ceramic>
      XML
    end

    it "returns an empty array for a valid instance" do
      parsed = mapper.from_xml(xml)

      expect(parsed.validate).to be_empty
    end

    it "returns an empty array for a valid instance with group choice" do
      parsed = mapper.from_xml(xml_with_alternate_selection)

      expect(parsed.validate).to be_empty
    end

    it "returns nil for a valid instance, if given attribute for sequence has correct order" do
      parsed = mapper.from_xml(xml)

      expect(parsed.validate!).to be_nil
    end

    it "returns nil for a valid instance with different options, if given attribute for sequence has correct order" do
      parsed = mapper.from_xml(xml_with_alternate_selection)

      expect(parsed.validate!).to be_nil
    end

    it "raises error, if given attributes order is incorrect in sequence" do
      xml = <<~XML
        <Ceramic>
          <name>Vase</name>
          <color>Blue</color>
          <type>Decorative</type>
          <material>Porcelain</material>
          <origin>China</origin>
          <pattern>Floral</pattern>
          <size>Medium</size>
          <usage>Indoor</usage>
          <condition>New</condition>
          <location>Gallery</location>
          <price>100</price>
        </Ceramic>
      XML

      parsed = mapper.from_xml(xml)
      expect { parsed.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("Elements must be present in the specified order")
      end
    end

    it "raises error, if not all attributes of the sequence specified" do
      xml = <<~XML
        <Ceramic>
          <type>Decorative</type>
          <material>Porcelain</material>
          <origin>China</origin>
          <usage>Indoor</usage>
          <condition>New</condition>
          <location>Gallery</location>
        </Ceramic>
      XML

      parsed = mapper.from_xml(xml)
      expect { parsed.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("Elements must be present in the specified order")
      end
    end
  end

  context "with explicit element mappings" do
    let(:mapper) { SequenceSpec::SequenceWithExplicitMapping }

    it "returns an empty array for a valid instance" do
      xml = <<~XML
        <SequenceWithExplicitMapping>
          <id>1</id>
          <bold>Light</bold>
          <italic>Format</italic>
        </SequenceWithExplicitMapping>
      XML

      parsed = mapper.from_xml(xml)

      expect(parsed.validate).to be_empty
    end

    it "returns an empty array for a valid instance, if elements are in defined order" do
      xml = <<~XML
        <SequenceWithExplicitMapping>
          <id>1</id>
          <bold>Light</bold>
          <italic>Format</italic>
        </SequenceWithExplicitMapping>
      XML

      parsed = mapper.from_xml(xml)

      expect(parsed.validate!).to be_nil
    end
  end

  context "with xml attribute" do
    let(:mapper) { SequenceSpec::SequenceWithXmlAttribute }

    it "raises error, if xml attribute is given in sequence" do
      xml = <<~XML
        <SequenceWithXmlAttribute city="DC">
          <town>Alabama</town>
          USA
        </SequenceWithXmlAttribute>
      XML

      parsed = mapper.from_xml(xml)
      expect { parsed.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("Elements must be present in the specified order")
      end
    end
  end
end
