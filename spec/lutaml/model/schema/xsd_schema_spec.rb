require "spec_helper"
require "lutaml/model/schema"
require "bigdecimal"

module SchemaGeneration
  class Glaze < Lutaml::Model::Serializable
    attribute :color, Lutaml::Model::Type::String
    attribute :finish, Lutaml::Model::Type::String
  end

  class Vase < Lutaml::Model::Serializable
    attribute :height, Lutaml::Model::Type::Float
    attribute :diameter, Lutaml::Model::Type::Float
    attribute :glaze, Glaze
    attribute :materials, Lutaml::Model::Type::String, collection: true
  end

  class Percent < Lutaml::Model::Type::Integer
    inclusive min: 0, max: 100
  end

  class Money < Lutaml::Model::Type::Decimal
    exclusive min: BigDecimal("1.5")
    total_digits 5
    fraction_digits 2
  end

  class Code < Lutaml::Model::Type::String
    length min: 2, max: 8
    enumeration "AB", "CD"
    white_space :collapse
    pattern(/[A-Z]+/)
  end

  class Tag < Lutaml::Model::Type::String
    length min: 1, max: 3
  end

  # Two accumulated patterns are conjunctive (a value must match BOTH). XSD has
  # no way to express that in one restriction (sibling <xs:pattern> is OR), so
  # exporting it must fail fast rather than silently emit a weaker OR schema.
  class MultiPattern < Lutaml::Model::Type::String
    pattern(/\A\d+\z/)
    pattern(/\A.{4}\z/)
  end

  class MultiPatternHolder < Lutaml::Model::Serializable
    attribute :field, MultiPattern
    xml do
      root "MultiPatternHolder"
      map_element "field", to: :field
    end
  end

  class Record < Lutaml::Model::Serializable
    attribute :code, Code
    attribute :percent, Percent
    attribute :money, Money
    attribute :tags, Tag, collection: true
    attribute :note, Lutaml::Model::Type::String

    xml do
      root "Record"
      map_attribute "code", to: :code
      map_element "percent", to: :percent
      map_element "money", to: :money
      map_element "tags", to: :tags
      map_element "note", to: :note
    end
  end
end

RSpec.describe Lutaml::Xml::Schema::XsdSchema do
  describe ".generate" do
    it "generates an XSD schema for nested Serialize objects" do
      schema = described_class.generate(SchemaGeneration::Vase, pretty: true)

      expected_schema = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <schema xmlns="http://www.w3.org/2001/XMLSchema">
          <element name="SchemaGeneration::Vase">
            <complexType>
              <sequence>
                <element name="height" type="xs:float"/>
                <element name="diameter" type="xs:float"/>
                <element name="glaze">
                  <complexType>
                    <sequence>
                      <element name="color" type="xs:string"/>
                      <element name="finish" type="xs:string"/>
                    </sequence>
                  </complexType>
                </element>
                <element name="materials" minOccurs="0" maxOccurs="unbounded">
                  <complexType>
                    <sequence>
                      <element name="item" type="xs:string"/>
                    </sequence>
                  </complexType>
                </element>
              </sequence>
            </complexType>
          </element>
        </schema>
      XSD

      expect(schema).to eq(expected_schema)
    end

    context "with constrained value types (issue #191)" do
      subject(:schema) do
        described_class.generate(SchemaGeneration::Record, pretty: true)
      end

      # Indentation depends on nesting depth; compare with leading whitespace
      # stripped so the assertions pin structure and order, not column counts.
      let(:unindented) { schema.gsub(/^ +/, "") }

      it "inlines an xs:restriction with facets in canonical order for an attribute" do
        expect(unindented).to include(<<~XSD.chomp)
          <attribute name="code">
          <simpleType>
          <restriction base="xs:string">
          <minLength value="2"/>
          <maxLength value="8"/>
          <enumeration value="AB"/>
          <enumeration value="CD"/>
          <whiteSpace value="collapse"/>
          <pattern value="[A-Z]+"/>
          </restriction>
          </simpleType>
          </attribute>
        XSD
      end

      it "emits integer inclusive bounds on a simple element" do
        expect(unindented).to include(<<~XSD.chomp)
          <element name="percent">
          <simpleType>
          <restriction base="xs:integer">
          <minInclusive value="0"/>
          <maxInclusive value="100"/>
          </restriction>
          </simpleType>
          </element>
        XSD
      end

      it "renders decimal bounds and digit facets with exact lexical values" do
        expect(schema).to include('<restriction base="xs:decimal">')
        expect(schema).to include('<minExclusive value="1.5"/>')
        expect(schema).to include('<totalDigits value="5"/>')
        expect(schema).to include('<fractionDigits value="2"/>')
      end

      it "inlines the restriction on the item of a constrained collection" do
        expect(unindented).to include(<<~XSD.chomp)
          <element name="item">
          <simpleType>
          <restriction base="xs:string">
          <minLength value="1"/>
          <maxLength value="3"/>
          </restriction>
          </simpleType>
          </element>
        XSD
      end

      it "leaves an unconstrained type as a flat type reference" do
        expect(schema).to include('<element name="note" type="xs:string"/>')
        expect(schema).not_to match(/name="code"[^>]*type=/)
      end

      it "fails fast on conjunctive patterns rather than emitting OR siblings" do
        expect do
          described_class.generate(SchemaGeneration::MultiPatternHolder)
        end.to raise_error(Lutaml::Model::Error, /conjunctive pattern/)
      end
    end
  end
end
