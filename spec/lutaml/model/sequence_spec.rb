require "spec_helper"
require "lutaml/model"

module Sequence
  class Person < Lutaml::Model::Serializable
    attribute :test, :string

    sequence do
      attribute :name, :string
      attribute :age, :integer
      attribute :gender, :string

      sequence do
        attribute :caste, :string
        attribute :degree, :string

        sequence do
          attribute :routine, :string
        end
      end

      sequence do
        attribute :occupation, :string
        attribute :vehicle, :string
      end
    end

    sequence do
      choice do
        group do
          sequence do
            attribute :type, :string
            attribute :is_lazy, :boolean
          end
        end

        attribute :status, :string
      end

      choice do
        attribute :job_title, :string
        attribute :work_experience, :integer
      end

      attribute :dob, :string
      attribute :view, :string
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
    let(:mapper) { Sequence::Person }

    let(:xml) do
      <<~XML
        <Person>
          <name>Starc</name>
          <age>35</age>
          <gender>male</gender>
          <caste>aussie</caste>
          <degree>fitness</degree>
          <routine>tough</routine>
          <occupation>cricketer</occupation>
          <vehicle>car</vehicle>
          <status>active</status>
          <job_title>ASE</job_title>
          <dob>march</dob>
          <view>desert</view>
        </Person>
      XML
    end

    let(:xml_with_alternate_selection) do
      <<~XML
        <Person>
          <name>Starc</name>
          <age>35</age>
          <gender>male</gender>
          <caste>aussie</caste>
          <degree>fitness</degree>
          <routine>tough</routine>
          <occupation>cricketer</occupation>
          <vehicle>car</vehicle>
          <type>night</type>
          <is_lazy>false</is_lazy>
          <work_experience>4</work_experience>
          <dob>march</dob>
          <view>desert</view>
        </Person>
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
        <Person>
          <name>Starc</name>
          <gender>male</gender>
          <age>35</age>
          <degree>fitness</degree>
          <caste>aussie</caste>
          <routine>tough</routine>
          <vehicle>car</vehicle>
          <occupation>cricketer</occupation>
          <status>active</status>
          <view>desert</view>
          <dob>march</dob>
        </Person>
      XML

      parsed = mapper.from_xml(xml)
      expect { parsed.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("Elements must be present in the specified order")
      end
    end

    it "raises error, if not all attributes of the sequence specified" do
      xml = <<~XML
        <Person>
          <age>35</age>
          <degree>fitness</degree>
          <caste>aussie</caste>
          <occupation>cricketer</occupation>
          <status>active</status>
          <view>desert</view>
        </Person>
      XML

      parsed = mapper.from_xml(xml)
      expect { parsed.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("Elements must be present in the specified order")
      end
    end
  end

  context "with explicit element mappings" do
    let(:mapper) { Sequence::SequenceWithExplicitMapping }

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
    let(:mapper) { Sequence::SequenceWithXmlAttribute }

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
