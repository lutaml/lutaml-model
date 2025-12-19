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
      element "Ceramic"
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
      element "collection"

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

  class Person < Lutaml::Model::Serializable
    attribute :first_name, :string
    attribute :last_name, :string
    choice do
      attribute :age, :integer
      attribute :dob, :string
    end
    choice(min: 1, max: 2) do
      attribute :email, :string, collection: 0..2
      attribute :phone, :string, collection: 0..2
      attribute :address, :string, collection: true
    end

    xml do
      element "Person"
      mixed_content

      sequence do
        map_element :FirstName, to: :first_name
        map_element :LastName, to: :last_name
        map_element :Age, to: :age
        map_element :Dob, to: :dob
        map_element :Email, to: :email
        map_element :Phone, to: :phone
        map_element :Address, to: :address
      end
    end
  end

  class User < Person
    restrict :email, collection: 1..
  end

  class Mrow < Lutaml::Model::Serializable
    choice(min: 1, max: 2) do
      attribute :mi, :string, collection: 1..Float::INFINITY
      attribute :mo, :string, collection: 1..Float::INFINITY
    end

    choice(min: 0, max: 2) do
      attribute :ms, :string, collection: (1..)
      attribute :mn, :string, collection: (1..)
    end

    xml do
      element "mstyle"

      sequence do
        map_element :mi, to: :mi
        map_element :mo, to: :mo
        map_element :ms, to: :ms
        map_element :mn, to: :mn
      end
    end
  end

  class Mstyle < Lutaml::Model::Serializable
    choice(min: 0, max: 100) do
      attribute :mrow, Mrow, collection: 1..Float::INFINITY
      attribute :mstyle, Mstyle, collection: 1..Float::INFINITY
    end

    xml do
      element "mstyle"

      sequence do
        map_element :mrow, to: :mrow
        map_element :mstyle, to: :mstyle
      end
    end
  end

  class Math < Lutaml::Model::Serializable
    choice(min: 1, max: 2) do
      attribute :mstyle, Mstyle, collection: (1..)
      attribute :mrow, Mrow, collection: (1..Float::INFINITY)
    end
    choice(min: 1, max: 3) do
      attribute :mi, :string, collection: true
      attribute :mo, :string, collection: 1..1
      attribute :mn, :integer, collection: 0..1
    end
    attribute :ms, :string, collection: true

    xml do
      element "math"

      sequence do
        map_element :mstyle, to: :mstyle
        map_element :mrow, to: :mrow
        map_element :mi, to: :mi
        map_element :ms, to: :ms
        map_element :mo, to: :mo
        map_element :mn, to: :mn
      end
    end
  end

  class R < Lutaml::Model::Serializable
    choice(min: 1, max: Float::INFINITY) do
      attribute :t, :string, collection: 1..Float::INFINITY
      choice(min: 1, max: Float::INFINITY) do
        attribute :r, R, collection: 1..Float::INFINITY
      end
    end

    xml do
      element "r"
      ordered

      sequence do
        map_element :t, to: :t
        map_element :r, to: :r
      end
    end
  end

  class OMath < Lutaml::Model::Serializable
    choice(min: 1, max: 3) do
      attribute :t, :string, collection: 1..Float::INFINITY
      attribute :r, R, collection: 0..Float::INFINITY
    end

    xml do
      element "oMath"
      ordered

      sequence do
        map_element :t, to: :t
        map_element :r, to: :r
      end
    end
  end

  class OMathPara < Lutaml::Model::Serializable
    attribute :omath, OMath, collection: true

    xml do
      element "oMathPara"
      ordered

      sequence do
        map_element :oMath, to: :omath
      end
    end
  end
end

RSpec.describe "Sequence" do
  describe "with nesting sequence" do
    subject(:mapper) { SequenceSpec::Ceramic }

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
        expect { mapper.from_xml(xml).validate! }.not_to raise_error
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
          SequenceSpec::CeramicCollection.from_xml(xml).validate!
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
          mapper.from_xml(xml).validate!
        end.to raise_error(Lutaml::Model::ValidationError) do |error|
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
      end.to raise_error(Lutaml::Model::UnknownSequenceMappingError,
                         "map_attribute is not allowed in sequence")
    end
  end

  describe "#validate_content!" do
    let(:sequence) do
      SequenceSpec::CeramicRestricted.mappings_for(:xml).element_sequence[0]
    end
    let(:klass) { SequenceSpec::CeramicRestricted }

    it "does not raise for correct order" do
      expect do
        sequence.validate_content!(
          ["tag", "id", "name", "type", "color", "bold", "text", "usage",
           "size"], klass.new
        )
      end
        .not_to raise_error
    end

    it "raises for incorrect order" do
      expect do
        sequence.validate_content!(
          ["tag", "name", "id", "type", "color", "bold", "text", "usage",
           "size"], klass.new
        )
      end
        .to raise_error(Lutaml::Model::IncorrectSequenceError)
    end

    it "raises for unknown tag" do
      expect do
        sequence.validate_content!(
          ["tag", "id", "name", "foo", "type", "color", "bold", "text", "usage",
           "size"], klass.new
        )
      end
        .to raise_error(Lutaml::Model::IncorrectSequenceError)
    end

    it "raises error for missing required tag" do
      expect do
        sequence.validate_content!(
          ["tag", "id", "name", "type", "color", "bold", "text",
           "usage"], klass.new
        )
      end
        .to raise_error(Lutaml::Model::ElementCountOutOfRangeError)
    end

    context "when processing XML with correct sequence, including choice and collection attributes" do
      let(:basic_xml) do
        <<~XML
          <Person>
            <FirstName>Dale</FirstName>
            <LastName>Steyn</LastName>
            <Age>30</Age>
            <Email>alice@example.com</Email>
            <Email>alice1@example.com</Email>
          </Person>
        XML
      end

      let(:phone_numbered_xml) do
        <<~XML
          <Person>
            <FirstName>Dale</FirstName>
            <LastName>Steyn</LastName>
            <Age>30</Age>
            <Email>alice@example.com</Email>
            <Email>alice1@example.com</Email>
            <Phone>+1234567890</Phone>
          </Person>
        XML
      end

      let(:addressed_xml) do
        <<~XML
          <Person>
            <FirstName>Dale</FirstName>
            <LastName>Steyn</LastName>
            <Age>30</Age>
            <Email>alice@example.com</Email>
            <Email>alice1@example.com</Email>
            <Address>Street number 1</Address>
            <Address>Street number 2</Address>
            <Address>Street number 3</Address>
            <Address>Street number 4</Address>
            <Address>Street number 5</Address>
            <Address>Street number 6</Address>
            <Address>Street number 7</Address>
            <Address>Street number 8</Address>
            <Address>Street number 9</Address>
            <Address>Street number *</Address>
          </Person>
        XML
      end

      it "validates successfully with basic XML including required choice and collection attributes" do
        expect do
          SequenceSpec::Person.from_xml(basic_xml).validate!
        end.not_to raise_error
      end

      it "validates successfully with basic XML with User class" do
        expect do
          SequenceSpec::User.from_xml(basic_xml).validate!
        end.not_to raise_error
      end

      it "validates successfully when XML contains multiple phone and email elements" do
        expect do
          SequenceSpec::Person.from_xml(phone_numbered_xml).validate!
        end.not_to raise_error
      end

      it "validates successfully when XML contains an unbounded collection of addresses" do
        expect do
          SequenceSpec::Person.from_xml(addressed_xml).validate!
        end.not_to raise_error
      end
    end

    context "when XML input is missing minimum required collection element" do
      let(:missing_age_choice_xml) do
        <<~XML
          <Person>
            <FirstName>Dale</FirstName>
            <LastName>Steyn</LastName>
            <Email>alice@example.com</Email>
            <Address>Street number *</Address>
          </Person>
        XML
      end

      it "raises an error when XML is missing a required choice attribute" do
        expect do
          SequenceSpec::Person.from_xml(missing_age_choice_xml).validate!
        end.to raise_error(Lutaml::Model::ValidationError)
      end
    end

    context "when processing sequence with choice and collection attributes" do
      context "when XML input has correct sequence of elements and choice attributes appearance count" do
        it "validates successfully with correct sequence of elements for Math class" do
          xml = <<~XML
            <math>
              <mstyle>
                <mrow>
                  <mi>as</mi>
                </mrow>
              </mstyle>
              <mi>y</mi>
              <ms>+</ms>
              <mo>=</mo>
              <mn>10</mn>
            </math>
          XML
          expect do
            SequenceSpec::Math.from_xml(xml).validate!
          end.not_to raise_error
        end

        it "validates successfully with correct sequence of choice elements for OMathPara class" do
          xml = <<~XML
            <oMathPara>
              <oMath>
                <t>Simple Text</t>
                <r>
                  <t>Another Simple Text</t>
                </r>
              </oMath>
            </oMathPara>
          XML
          expect do
            SequenceSpec::OMathPara.from_xml(xml).validate!
          end.not_to raise_error
        end

        it "validates successfully with correct sequence of nested choice elements for OMathPara class" do
          xml = <<~XML
            <oMathPara>
              <oMath>
                <t>Simple Text</t>
                <r>
                  <t>Another Simple Text</t>
                  <r>
                    <t>Another Simple Text</t>
                  </r>
                </r>
              </oMath>
            </oMathPara>
          XML
          expect do
            SequenceSpec::OMathPara.from_xml(xml).validate!
          end.not_to raise_error
        end

        it "validates successfully with empty OMathPara element" do
          expect do
            SequenceSpec::OMathPara.from_xml("<oMathPara/>").validate!
          end.not_to raise_error
        end
      end

      context "when XML input has incorrect sequence of elements and choice attributes appearance count" do
        it "raises error when r is empty but expected to contain at least one element" do
          xml = <<~XML
            <oMathPara>
              <oMath>
                <r/>
              </oMath>
            </oMathPara>
          XML
          expect do
            SequenceSpec::OMathPara.from_xml(xml).validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to eq("Attributes `[]` count is less than the lower bound `1`")
          end
        end

        it "raises error when any nested r is empty but expected to contain at least one element" do
          xml = <<~XML
            <oMathPara>
              <oMath>
                <r>
                  <r>
                    <r/>
                  </r>
                </r>
              </oMath>
            </oMathPara>
          XML
          expect do
            SequenceSpec::OMathPara.from_xml(xml).validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to eq("Attributes `[]` count is less than the lower bound `1`")
          end
        end

        it "raises error when mrow is empty but expected to contain at least one element" do
          xml = <<~XML
            <math>
              <mstyle>
                <mrow/>
              </mstyle>
              <mi>y</mi>
              <ms>+</ms>
              <mo>=</mo>
              <mn>10</mn>
            </math>
          XML
          expect do
            SequenceSpec::Math.from_xml(xml).validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to eq("Attributes `[]` count is less than the lower bound `1`")
          end
        end

        it "raises an error when choice elements count exceeds the max number of the choice" do
          xml = <<~XML
            <math>
              <mstyle>
                <mrow>
                  <mi>y</mi>
                  <mi>y</mi>
                  <mo>+</mo>
                  <mi>z</mi>
                  <mo>+</mo>
                </mrow>
              </mstyle>
            </math>
          XML
          expect do
            SequenceSpec::Math.from_xml(xml).validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.message).to eq("Attributes `[\"mi\", \"mo\"]` count exceeds the upper bound `2`")
          end
        end

        it "raises error when 'mn' choice element exceeds the max limit" do
          xml = <<~XML
            <math>
              <mstyle>
                <mrow>
                  <mi>as</mi>
                </mrow>
              </mstyle>
              <mi>y</mi>
              <ms>+</ms>
              <mo>=</mo>
              <mn>10</mn>
              <mn>10</mn>
              <mn>10</mn>
              <mn>10</mn>
              <mn>10</mn>
              <mn>10</mn>
            </math>
          XML
          expect do
            SequenceSpec::Math.from_xml(xml).validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.error_messages.join("\n")).to eq("Attributes `[\"mn\"]` count exceeds the upper bound `3`")
          end
        end

        it "raises error with missing 'mstyle' and 'mrow' choice elements" do
          xml = <<~XML
            <math>
              <mi>y</mi>
              <ms>+</ms>
              <mo>=</mo>
              <mn>10</mn>
            </math>
          XML
          expect do
            SequenceSpec::Math.from_xml(xml).validate!
          end.to raise_error(Lutaml::Model::ValidationError) do |error|
            expect(error.error_messages.join("\n")).to eq("Attributes `[]` count is less than the lower bound `1`")
          end
        end
      end
    end
  end
end
