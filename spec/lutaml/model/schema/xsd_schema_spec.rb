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

  # XSD patterns are implicitly whole-string anchored, so the Ruby \A...\z
  # anchors must be stripped on export or Nokogiri rejects the pattern.
  class Anchored < Lutaml::Model::Type::String
    pattern(/\A[A-Z]{3}\z/)
  end

  class AnchoredHolder < Lutaml::Model::Serializable
    attribute :field, Anchored
    xml do
      root "AnchoredHolder"
      map_element "field", to: :field
    end
  end

  # A lookahead is not expressible in XSD's regexp subset; export must raise
  # rather than emit invalid XSD.
  class Lookahead < Lutaml::Model::Type::String
    pattern(/(?=.*[0-9])[a-z0-9]+/)
  end

  class LookaheadHolder < Lutaml::Model::Serializable
    attribute :field, Lookahead
    xml do
      root "LookaheadHolder"
      map_element "field", to: :field
    end
  end

  # A case-insensitive flag cannot be expressed in XSD; export must raise
  # rather than silently emit a case-sensitive pattern.
  class FlaggedPattern < Lutaml::Model::Type::String
    pattern(/[a-z]+/i)
  end

  class FlaggedHolder < Lutaml::Model::Serializable
    attribute :field, FlaggedPattern
    xml do
      root "FlaggedHolder"
      map_element "field", to: :field
    end
  end

  # Layer-1 attribute facets (no Layer-2 constrained type) must still emit an
  # inline xs:restriction so the schema matches what the model enforces.
  class Layered < Lutaml::Model::Serializable
    attribute :age, :integer, min: 0, max: 120
    attribute :code, :string, min_length: 2, max_length: 8
    xml do
      root "Layered"
      map_element "age", to: :age
      map_element "code", to: :code
    end
  end

  # The pre-#191 values:/pattern: options are enforced at runtime and must also
  # reach the exported schema.
  class LegacyOptions < Lutaml::Model::Serializable
    attribute :state, :string, values: %w[on off]
    attribute :ref, :string, pattern: /[A-Z]{2}/
    xml do
      root "LegacyOptions"
      map_element "state", to: :state
      map_element "ref", to: :ref
    end
  end

  # A Layer-1 option (max: 50) that tightens a Layer-2 type (Percent, max 100):
  # the merge is consistent, so export must emit the tighter bound, not raise.
  class MergedLayers < Lutaml::Model::Serializable
    attribute :n, Percent, max: 50
    xml do
      root "MergedLayers"
      map_element "n", to: :n
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

    context "with a Ruby pattern exported to XSD (issue #191)" do
      it "strips the Ruby whole-string anchors" do
        schema = described_class.generate(SchemaGeneration::AnchoredHolder)

        expect(schema).to include('<pattern value="[A-Z]{3}"/>')
      end

      it "emits a pattern Nokogiri accepts as valid XSD" do
        schema = described_class.generate(SchemaGeneration::AnchoredHolder)
        value = schema[/<pattern value="([^"]*)"/, 1]
        wrapped = <<~XSD
          <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
            <xs:simpleType name="T">
              <xs:restriction base="xs:string">
                <xs:pattern value="#{value}"/>
              </xs:restriction>
            </xs:simpleType>
          </xs:schema>
        XSD

        expect { Nokogiri::XML::Schema(wrapped) }.not_to raise_error
      end

      it "raises for a construct XSD cannot express" do
        expect do
          described_class.generate(SchemaGeneration::LookaheadHolder)
        end.to raise_error(Lutaml::Model::Error, /not expressible/)
      end

      it "raises for a regexp flag XSD cannot express" do
        expect do
          described_class.generate(SchemaGeneration::FlaggedHolder)
        end.to raise_error(Lutaml::Model::Error, /i\/m\/x flags/)
      end

      it "raises for a lazy quantifier XSD cannot express" do
        holder = Class.new(Lutaml::Model::Serializable) do
          attribute :field, Class.new(Lutaml::Model::Type::String) {
            pattern(/a+?/)
          }
          xml do
            root "LazyHolder"
            map_element "field", to: :field
          end
        end

        expect { described_class.generate(holder) }
          .to raise_error(Lutaml::Model::Error, /not expressible in XSD/)
      end

      # Backslash-run parity: `\\z` is an escaped backslash + literal "z", not
      # the `\z` anchor, so it must survive stripping (and be valid XSD) rather
      # than being truncated to a dangling backslash and spuriously rejected.
      it "keeps a literal escaped-backslash before z (even run)" do
        holder = Class.new(Lutaml::Model::Serializable) do
          attribute :field, Class.new(Lutaml::Model::Type::String) {
            pattern(/\\z/)
          }
          xml do
            root "BackslashZ"
            map_element "field", to: :field
          end
        end

        expect(described_class.generate(holder))
          .to include('<pattern value="\\\\z"/>')
      end

      # `\\$` is an escaped backslash followed by the end anchor `$` (even run
      # before `$`), so the anchor strips, leaving the literal backslash.
      it "strips a trailing $ anchor after an escaped backslash" do
        holder = Class.new(Lutaml::Model::Serializable) do
          attribute :field, Class.new(Lutaml::Model::Type::String) {
            pattern(/\\$/)
          }
          xml do
            root "BackslashDollar"
            map_element "field", to: :field
          end
        end

        expect(described_class.generate(holder))
          .to include('<pattern value="\\\\"/>')
      end
    end

    context "with Layer-1 attribute facets (issue #191)" do
      subject(:schema) do
        described_class.generate(SchemaGeneration::Layered, pretty: true)
      end

      let(:unindented) { schema.gsub(/^ +/, "") }

      it "inlines an xs:restriction for attribute min/max bounds" do
        expect(unindented).to include(<<~XSD.chomp)
          <element name="age">
          <simpleType>
          <restriction base="xs:integer">
          <minInclusive value="0"/>
          <maxInclusive value="120"/>
          </restriction>
          </simpleType>
          </element>
        XSD
      end

      it "inlines an xs:restriction for attribute length bounds" do
        expect(unindented).to include(<<~XSD.chomp)
          <element name="code">
          <simpleType>
          <restriction base="xs:string">
          <minLength value="2"/>
          <maxLength value="8"/>
          </restriction>
          </simpleType>
          </element>
        XSD
      end

      it "emits the tighter merged bound without a spurious raise" do
        schema = described_class.generate(SchemaGeneration::MergedLayers)

        expect(schema).to include('<minInclusive value="0"/>')
        expect(schema).to include('<maxInclusive value="50"/>')
      end

      it "emits the pre-#191 values:/pattern: options as facets" do
        schema = described_class.generate(SchemaGeneration::LegacyOptions)

        expect(schema).to include('<enumeration value="on"/>')
        expect(schema).to include('<enumeration value="off"/>')
        expect(schema).to include('<pattern value="[A-Z]{2}"/>')
      end

      it "intersects a values: option with a Layer-2 enumeration" do
        enum_type = Class.new(Lutaml::Model::Type::String) do
          enumeration "a", "b", "c"
        end
        model = Class.new(Lutaml::Model::Serializable) do
          attribute :s, enum_type, values: %w[a b]
          xml do
            root "R"
            map_element "s", to: :s
          end
        end
        schema = described_class.generate(model)

        expect(schema).to include('<enumeration value="a"/>')
        expect(schema).to include('<enumeration value="b"/>')
        expect(schema).not_to include('<enumeration value="c"/>')
      end

      it "raises when values: is disjoint from the Layer-2 enumeration" do
        enum_type = Class.new(Lutaml::Model::Type::String) do
          enumeration "a", "b"
        end
        model = Class.new(Lutaml::Model::Serializable) do
          attribute :s, enum_type, values: %w[c d]
          xml do
            root "R"
            map_element "s", to: :s
          end
        end

        expect { described_class.generate(model) }
          .to raise_error(ArgumentError, /enumeration allows no values/)
      end

      # An explicit `min: nil` means "no bound"; it must not leave a nil facet
      # that emits an empty <xs:restriction> around the element.
      it "treats an explicit nil bound as absent (no empty restriction)" do
        model = Class.new(Lutaml::Model::Serializable) do
          attribute :x, :integer, min: nil
          xml do
            root "R"
            map_element "x", to: :x
          end
        end
        schema = described_class.generate(model)

        expect(schema).to include('<element name="x" type="xs:integer"/>')
        expect(schema).not_to include("<restriction")
      end
    end
  end
end
