require "spec_helper"
require "lutaml/model"

module SequenceSpec
  class Ceramic < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :name, :string
    attribute :type, :string
    attribute :color, :string
    attribute :bold, :string
    attribute :text, :string
    attribute :usage, :string
    attribute :size, :string
    attribute :first_name, :string
    attribute :last_name, :string
    attribute :tag, :string
    attribute :temperature, :string

    xml do
      root "Ceramic"
      map_element :tag, to: :tag

      sequence do
        map_element :id, to: :id
        map_element :name, to: :name
        map_element :type, to: :type
        map_element :color, to: :color
        map_element :bold, to: :bold
        map_element :text, to: :text
        sequence do
          map_element :usage, to: :usage
          map_element :size, to: :size
        end
      end

      sequence do
        map_element :first_name, to: :first_name
        map_element :last_name, to: :last_name
      end

      map_element :temperature, to: :temperature
    end
  end

  class CeramicCollection < Lutaml::Model::Serializable
    attribute :ceramic, Ceramic, collection: 1..2

    xml do
      root "collection"
      map_element "ceramic", to: :ceramic
    end
  end

  class CeramicRestricted < Ceramic
    restrict :id, collection: 0..1
    restrict :name, collection: 0..1
    restrict :type, collection: 0..1
    restrict :color, collection: 0..1
    restrict :bold, collection: 0..1
    restrict :text, collection: 0..1
    restrict :usage, collection: 0..1
    restrict :size, collection: 1..2
  end
end

RSpec.describe "Sequence" do
  context "with nesting sequence" do
    let(:mapper) { SequenceSpec::Ceramic }

    context "when given attribute for sequence has correct order" do
      let(:xml) do
        <<~XML
          <Ceramic>
            <tag>Nik</tag>
            <id>1</id>
            <name>Vase</name>
            <type>Decorative</type>
            <color>Blue</color>
            <bold>Heading</bold>
            <text>Header</text>
            <usage>Indoor</usage>
            <size>Medium</size>
            <first_name>Dale</first_name>
            <last_name>Steyn</last_name>
            <temperature>Normal</temperature>
          </Ceramic>
        XML
      end

      it "does not raise error" do
        expect { mapper.from_xml(xml) }.not_to raise_error
      end
    end

    context "when given attribute for sequence collection has correct order" do
      let(:xml) do
        <<~XML
          <collection>
            <ceramic>
              <tag>Nik</tag>
              <id>1</id>
              <name>Vase</name>
              <type>Decorative</type>
              <color>Blue</color>
              <bold>Heading</bold>
              <text>Header</text>
              <usage>Indoor</usage>
              <size>Medium</size>
              <first_name>Dale</first_name>
              <last_name>Steyn</last_name>
              <temperature>Normal</temperature>
            </ceramic>
            <ceramic>
              <tag>Nik</tag>
              <id>1</id>
              <name>Vase</name>
              <type>Decorative</type>
              <color>Blue</color>
              <bold>Heading</bold>
              <text>Header</text>
              <usage>Indoor</usage>
              <size>Medium</size>
              <first_name>Dale</first_name>
              <last_name>Steyn</last_name>
              <temperature>Normal</temperature>
            </ceramic>
          </collection>
        XML
      end

      it "does not raise error" do
        expect do
          SequenceSpec::CeramicCollection.from_xml(xml)
        end.not_to raise_error
      end
    end

    context "when given attributes order is incorrect in sequence" do
      let(:xml) do
        <<~XML
          <Ceramic>
            <tag>Nik</tag>
            <temperature>High</temperature>
            <first_name>Micheal</first_name>
            <id>1</id>
            <name>Vase</name>
            <type>Decorative</type>
            <color>Blue</color>
            <bold>Heading</bold>
            <usage>Indoor</usage>
            <size>Medium</size>
            <last_name>Johnson</last_name>
            <text>Header</text>
          </Ceramic>
        XML
      end

      it "raises IncorrectSequenceError error" do
        expect do
          mapper.from_xml(xml)
        end.to raise_error(Lutaml::Model::IncorrectSequenceError) do |error|
          expect(error.message).to eq("Element `usage` does not match the expected sequence order element `text`")
        end
      end
    end

    context "when given attributes order is incorrect in sequence collection" do
      let(:xml) do
        <<~XML
          <collection>
            <ceramic>
              <id>1</id>
              <name>Vase</name>
              <type>Decorative</type>
              <color>Blue</color>
              <bold>Heading</bold>
              <text>Header</text>
              <usage>Indoor</usage>
              <size>Medium</size>
              <first_name>Dale</first_name>
              <last_name>Steyn</last_name>
              <temperature>Normal</temperature>
              <tag>Nik</tag>
            </ceramic>

            <ceramic>
              <id>2</id>
              <name>Nick</name>
              <type>Unique</type>
              <color>Red</color>
              <bold>Name</bold>
              <text>Body</text>
              <usage>Outdoor</usage>
              <size>Small</size>
              <first_name>Smith</first_name>
              <last_name>Ash</last_name>
              <temperature>High</temperature>
              <tag>Adid</tag>
            </ceramic>

            <ceramic>
              <id>3</id>
              <name>Starc</name>
              <type>Int</type>
              <color>White</color>
              <bold>Act</bold>
              <text>Footer</text>
              <usage>Nothing</usage>
              <size>Large</size>
              <first_name>Dale</first_name>
              <last_name>Steyn</last_name>
              <temperature>Normal</temperature>
              <tag>Bet</tag>
            </ceramic>
          </collection>
        XML
      end

      it "raises CollectionCountOutOfRangeError error" do
        expect do
          SequenceSpec::CeramicCollection.from_xml(xml).validate!
        end.to raise_error(Lutaml::Model::ValidationError) do |error|
          expect(error).to include(Lutaml::Model::CollectionCountOutOfRangeError)
          expect(error.error_messages).to eq(["ceramic count is 3, must be between 1 and 2"])
        end
      end
    end

    it "raises error, if mapping other map_element are defined in sequence" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :type, :string

          xml do
            sequence do
              map_attribute :type, to: :type
            end
          end
        end
      end.to raise_error(Lutaml::Model::UnknownSequenceMappingError, "map_attribute is not allowed in sequence")
    end
  end

  describe "#validate_content!" do
    let(:sequence) { SequenceSpec::CeramicRestricted.mappings_for(:xml).element_sequence[0] }
    let(:klass) { SequenceSpec::CeramicRestricted }

    it "does not raise for correct order" do
      expect { sequence.validate_content!(["tag", "id", "name", "type", "color", "bold", "text", "usage", "size"], klass) }
        .not_to raise_error
    end

    it "raises for incorrect order" do
      expect { sequence.validate_content!(["tag", "name", "id", "type", "color", "bold", "text", "usage", "size"], klass) }
        .to raise_error(Lutaml::Model::IncorrectSequenceError)
    end

    it "raises for unknown tag" do
      expect { sequence.validate_content!(["tag", "id", "name", "foo", "type", "color", "bold", "text", "usage", "size"], klass) }
        .to raise_error(Lutaml::Model::IncorrectSequenceError)
    end

    it "raises error for missing required tag" do
      expect { sequence.validate_content!(["tag", "id", "name", "type", "color", "bold", "text", "usage"], klass) }
        .to raise_error(Lutaml::Model::ElementCountOutOfRangeError)
    end
  end
end
