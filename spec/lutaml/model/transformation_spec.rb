require "spec_helper"

module TransformationSpec
  # Class with only attribute-level transformations
  class AttributeTransformPerson < Lutaml::Model::Serializable
    attribute :name, :string, transform: {
      export: ->(value) { value.to_s.upcase },
    }
    attribute :email, :string, transform: {
      import: ->(value) { "#{value}@example.com" },
    }
    attribute :tags, :string, collection: true, transform: {
      export: ->(value) { value.map(&:upcase) },
      import: ->(value) { value.map { |v| "#{v}-1" } },
    }
  end

  # Class with only mapping-level transformations
  class MappingTransformPerson < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :email, :string
    attribute :tags, :string, collection: true

    json do
      map "fullName", to: :name, transform: {
        export: ->(value) { "Dr. #{value}" },
      }
      map "emailAddress", to: :email, transform: {
        import: ->(value) { value.gsub("at", "@") },
      }
      map "labels", to: :tags, transform: {
        export: ->(value) { value.join("-|-") },
        import: ->(value) { value.split("|") },
      }
    end

    xml do
      root "person"
      map_element "full-name", to: :name, transform: {
        export: ->(value) { "Dr. #{value}" },
      }
      map_element "email-address", to: :email, transform: {
        import: ->(value) { value.gsub("at", "@") },
      }
      map_element "labels", to: :tags, transform: {
        export: ->(value) { value.join("-|-") },
        import: ->(value) { value.split("|") },
      }
    end
  end

  # Class with both attribute and mapping transformations
  class CombinedTransformPerson < Lutaml::Model::Serializable
    attribute :name, :string, transform: {
      export: ->(value) { value.to_s.capitalize },
      import: ->(value) { value.to_s.downcase },
    }
    attribute :email, :string, transform: {
      export: lambda(&:upcase),
      import: lambda(&:downcase),
    }
    attribute :tags, :string, collection: true, transform: {
      export: ->(value) { value.map(&:upcase) },
      import: ->(value) { value.map { |v| "#{v}-1" } },
    }

    json do
      map "fullName", to: :name, transform: {
        export: ->(value) { "Prof. #{value}" },
        import: ->(value) { value.gsub("Prof. ", "") },
      }
      map "contactEmail", to: :email, transform: {
        export: ->(value) { "contact+#{value}" },
        import: ->(value) { value.gsub("contact+", "") },
      }
      map "skills", to: :tags
    end

    xml do
      root "person"
      map_element "full-name", to: :name, transform: {
        export: ->(value) { "Prof. #{value}" },
        import: ->(value) { value.gsub("Prof. ", "") },
      }
      map_attribute "contact-email", to: :email, transform: {
        export: ->(value) { "contact+#{value}" },
        import: ->(value) { value.gsub("contact+", "") },
      }
      map_element "skills", to: :tags
    end
  end

  class RoundTripTransformations < Lutaml::Model::Serializable
    attribute :number, :string, transform: {
      import: ->(value) { (value.to_f + 1).to_s },
      export: ->(value) { (value.to_f - 1).to_s },
    }

    json do
      map "number", to: :number, transform: {
        import: ->(value) { ((value.to_f * 10) + 1).to_s },
        export: ->(value) { ((value.to_f - 1) / 10.0).to_s },
      }
    end

    xml do
      root "RoundTripTransformations"

      map_element "number", to: :number, transform: {
        import: ->(value) { ((value.to_f * 10) + 1).to_s },
        export: ->(value) { ((value.to_f - 1) / 10.0).to_s },
      }
    end
  end

  # Class-based transformer specs
  class MeasurementTransformer < Lutaml::Model::ValueTransformer
    def to_json(*_args)
      return value if value.nil?

      "#{value[:value]} #{value[:unit]}"
    end

    def from_json(value)
      number, unit = value.split
      { value: number.to_f, unit: unit }
    end

    def from_xml(value)
      number, unit = value.split
      { value: number.to_f, unit: unit }
    end

    def to_xml(*_args)
      return value if value.nil?

      "#{value[:value]} #{value[:unit]}"
    end
  end

  class CeramicModel < Lutaml::Model::Serializable
    attribute :measurement, :hash, transform: MeasurementTransformer
  end

  # Class-based transformers for string types
  class NameTransformer < Lutaml::Model::ValueTransformer
    def to_json(*_args)
      value.to_s.upcase
    end

    def from_json(val)
      val.to_s.reverse
    end

    def to_xml(*_args)
      value.to_s.upcase
    end

    def from_xml(val)
      val.to_s.reverse
    end
  end

  class EmailTransformer < Lutaml::Model::ValueTransformer
    def to_json(*_args)
      "user:#{value}"
    end

    def from_json(val)
      val.gsub("user:", "")
    end

    def to_xml(*_args)
      "user:#{value}"
    end

    def from_xml(val)
      val.gsub("user:", "")
    end
  end

  class TagsTransformer < Lutaml::Model::ValueTransformer
    def to_json(*_args)
      value.map(&:capitalize)
    end

    def from_json(val)
      val.map(&:downcase)
    end

    def to_xml(*_args)
      value.map(&:capitalize)
    end

    def from_xml(val)
      val.map(&:downcase)
    end
  end

  # Combined transformation class that uses multiple class-based transformers
  class CombinedTransformer < Lutaml::Model::ValueTransformer
    def to_json(*_args)
      return value if value.nil?

      case value
      when Hash
        # Transform a hash like { name: "john", prefix: "Dr." } to "Dr. JOHN"
        "#{value[:prefix]} #{value[:name].upcase}"
      else
        value.to_s.upcase
      end
    end

    def from_json(val)
      # Transform "Dr. JOHN" back to { name: "john", prefix: "Dr." }
      parts = val.split(" ", 2)
      { prefix: parts[0], name: parts[1]&.downcase }
    end

    def to_xml(*_args)
      return value if value.nil?

      case value
      when Hash
        "#{value[:prefix]} #{value[:name].upcase}"
      else
        value.to_s.upcase
      end
    end

    def from_xml(val)
      parts = val.split(" ", 2)
      { prefix: parts[0], name: parts[1]&.downcase }
    end
  end

  class StringTransformModel < Lutaml::Model::Serializable
    attribute :name, :string, transform: NameTransformer
    attribute :email, :string, transform: EmailTransformer
    attribute :tags, :string, collection: true, transform: TagsTransformer

    json do
      map "name", to: :name
      map "email", to: :email
      map "tags", to: :tags
    end
    xml do
      root "StringTransformModel"
      map_element "name", to: :name
      map_element "email", to: :email
      map_element "tags", to: :tags
    end
  end

  # Combined transformation: both attribute-level AND mapping-level transformers on same field
  class PrefixTransformer < Lutaml::Model::ValueTransformer
    def to_json(*_args)
      "PREFIX:#{value}"
    end

    def from_json(val)
      val.gsub("PREFIX:", "")
    end

    def to_xml(*_args)
      "PREFIX:#{value}"
    end

    def from_xml(val)
      val.gsub("PREFIX:", "")
    end
  end

  class SuffixTransformer < Lutaml::Model::ValueTransformer
    def to_json(*_args)
      "#{value}:SUFFIX"
    end

    def from_json(val)
      val.gsub(":SUFFIX", "")
    end

    def to_xml(*_args)
      "#{value}:SUFFIX"
    end

    def from_xml(val)
      val.gsub(":SUFFIX", "")
    end
  end

  class CombinedTransformModel < Lutaml::Model::Serializable
    # This attribute has BOTH attribute-level AND mapping-level transformations
    attribute :title, :string, transform: PrefixTransformer

    json do
      # This mapping ALSO has a transformer - both will be applied!
      # Order: input (from_format): mapping_rule transformer, then attribute transformer
      # Order: output (to_format): attribute transformer, then mapping_rule transformer
      map "title", to: :title, transform: SuffixTransformer
    end
    xml do
      root "CombinedTransformModel"
      map_element "title", to: :title, transform: SuffixTransformer
    end
  end
end

RSpec.describe "Value Transformations" do
  describe "Attribute-only transformations" do
    let(:attribute_person) do
      TransformationSpec::AttributeTransformPerson.new(
        name: "john",
        email: "smith",
        tags: ["ruby", "rails"],
      )
    end

    let(:expected_xml) do
      <<~XML
        <AttributeTransformPerson>
          <name>JOHN</name>
          <email>smith</email>
          <tags>RUBY</tags>
          <tags>RAILS</tags>
        </AttributeTransformPerson>
      XML
    end

    it "applies attribute transformations during serialization" do
      parsed_json = JSON.parse(attribute_person.to_json)
      expect(parsed_json["name"]).to eq("JOHN")
      expect(parsed_json["email"]).to eq("smith")
      expect(parsed_json["tags"]).to eq(["RUBY", "RAILS"])
    end

    it "applies attribute transformations during deserialization" do
      json = {
        "name" => "jane",
        "email" => "doe",
        "tags" => ["python", "django"],
      }.to_json

      parsed = TransformationSpec::AttributeTransformPerson.from_json(json)
      expect(parsed.name).to eq("jane")
      expect(parsed.email).to eq("doe@example.com")
      expect(parsed.tags).to eq(["python-1", "django-1"])
    end

    it "applies attribute transformations during XML serialization" do
      xml = attribute_person.to_xml
      expect(xml).to be_equivalent_to(expected_xml)
    end
  end

  describe "Mapping-only transformations" do
    let(:mapping_person) do
      TransformationSpec::MappingTransformPerson.new(
        name: "alice",
        email: "aliceattest.com",
        tags: ["developer", "architect"],
      )
    end

    let(:json) do
      {
        "fullName" => "Dr. bob",
        "emailAddress" => "bobattest.com",
        "labels" => "senior|lead",
      }.to_json
    end

    let(:parsed) do
      TransformationSpec::MappingTransformPerson.from_json(json)
    end

    let(:expected_xml) do
      <<~XML
        <person>
          <full-name>Dr. alice</full-name>
          <email-address>aliceattest.com</email-address>
          <labels>developer-|-architect</labels>
        </person>
      XML
    end

    it "applies mapping transformations during JSON serialization" do
      json = mapping_person.to_json
      parsed = JSON.parse(json)
      expect(parsed["fullName"]).to eq("Dr. alice")
      expect(parsed["emailAddress"]).to eq("aliceattest.com")
      expect(parsed["labels"]).to eq("developer-|-architect")
    end

    it "correctly deserialize name from JSON" do
      expect(parsed.name).to eq("Dr. bob")
    end

    it "correctly deserialize email from JSON" do
      expect(parsed.email).to eq("bob@test.com")
    end

    it "correctly deserialize tags from JSON" do
      expect(parsed.tags).to eq(["senior", "lead"])
    end

    it "applies mapping transformations during XML serialization" do
      xml = mapping_person.to_xml
      expect(xml).to be_equivalent_to(expected_xml)
    end
  end

  describe "Combined transformations" do
    let(:combined_person) do
      TransformationSpec::CombinedTransformPerson.new(
        name: "carol",
        email: "CAROL@TEST.COM",
        tags: ["manager", "agile"],
      )
    end

    let(:expected_xml) do
      <<~XML
        <person contact-email="contact+CAROL@TEST.COM">
          <full-name>Prof. Carol</full-name>
          <skills>MANAGER-1</skills>
          <skills>AGILE-1</skills>
        </person>
      XML
    end

    it "applies both transformations with correct precedence in JSON" do
      json = combined_person.to_json
      parsed = JSON.parse(json)

      expect(parsed["fullName"]).to eq("Prof. Carol")
      expect(parsed["contactEmail"]).to eq("contact+CAROL@TEST.COM")
    end

    it "handles round-trip transformations across formats" do
      # JSON -> Key-Value -> JSON cycle
      json = combined_person.to_json
      parsed_json = TransformationSpec::CombinedTransformPerson.from_json(json)
      expect(parsed_json.name).to eq("carol")
      expect(parsed_json.email).to eq("carol@test.com")
      expect(parsed_json.tags).to eq(["MANAGER-1", "AGILE-1"])
    end

    it "applies both transformations with correct precedence in XML" do
      xml = combined_person.to_xml
      parsed_xml = TransformationSpec::CombinedTransformPerson.from_xml(xml)
      expect(parsed_xml.to_xml).to be_equivalent_to(expected_xml)
    end
  end

  describe "Custom Transformations all mappings applied" do
    let(:xml) do
      <<~XML
        <RoundTripTransformations>
          <number>10.0</number>
        </RoundTripTransformations>
      XML
    end

    let(:json) do
      { number: "10.0" }.to_json
    end

    it "correctly round trips XML" do
      parsed = TransformationSpec::RoundTripTransformations.from_xml(xml)
      expect(parsed.to_xml).to be_equivalent_to(xml)
    end

    it "correctly round trips JSON" do
      parsed = TransformationSpec::RoundTripTransformations.from_json(json)
      expect(parsed.to_json).to be_equivalent_to(json)
    end
  end

  describe "Class-based transformations" do
    describe TransformationSpec::CeramicModel do
      let(:json) { '{"measurement": "10.0 cm"}' }
      let(:xml) do
        <<~XML
          <CeramicModel>
            <measurement>
              10.0 cm
            </measurement>
          </CeramicModel>
        XML
      end

      describe "JSON transformation" do
        it "deserializes measurement from JSON string" do
          model = described_class.from_json(json)
          expect(model.measurement).to eq({ value: 10.0, unit: "cm" })
        end

        it "serializes measurement to JSON string" do
          model = described_class.from_json(json)
          expect(model.to_json).to include('"measurement":"10.0 cm"')
        end
      end

      describe "XML transformation" do
        it "deserializes measurement from XML" do
          model = described_class.from_xml(xml)
          expect(model.measurement).to eq({ value: 10.0, unit: "cm" })
        end

        it "serializes measurement to XML" do
          model = described_class.from_xml(xml)
          expect(model.to_xml).to include("<measurement>10.0 cm</measurement>")
        end
      end

      describe "round-trip transformation" do
        it "keeps measurement consistent through JSON round-trip" do
          model = described_class.from_json(json)
          new_json = model.to_json
          model2 = described_class.from_json(new_json)
          expect(model2.measurement).to eq({ value: 10.0, unit: "cm" })
        end

        it "keeps measurement consistent through XML round-trip" do
          model = described_class.from_xml(xml)
          new_xml = model.to_xml
          model2 = described_class.from_xml(new_xml)
          expect(model2.measurement).to eq({ value: 10.0, unit: "cm" })
        end
      end

      describe "YAML format" do
        let(:yaml) { "---\nmeasurement:\n  value: 10\n  unit: cm\n" }

        it "does not transform measurement for YAML" do
          model = described_class.from_yaml(yaml)
          expect(model.measurement).to eq({ "value" => 10, "unit" => "cm" })
          expect(model.to_yaml).to include("value: 10")
          expect(model.to_yaml).to include("unit: cm")
        end
      end
    end

    describe TransformationSpec::StringTransformModel do
      let(:json) do
        '{"name": "alice", "email": "alice@example.com", "tags": ["ruby", "rails"]}'
      end
      let(:xml) do
        <<~XML
          <StringTransformModel>
            <name>bob</name>
            <email>user:bob@example.com</email>
            <tags>dev</tags>
            <tags>test</tags>
          </StringTransformModel>
        XML
      end

      it "applies string transformations during JSON serialization" do
        model = described_class.from_json(json)
        expect(model.name).to eq("ecila")
        expect(model.email).to eq("alice@example.com")
        expect(model.tags).to eq(["ruby", "rails"])
        json_out = model.to_json
        parsed = JSON.parse(json_out)
        expect(parsed["name"]).to eq("ECILA")
        expect(parsed["email"]).to eq("user:alice@example.com")
        expect(parsed["tags"]).to eq(["Ruby", "Rails"])
      end

      it "applies string transformations during XML serialization" do
        model = described_class.from_xml(xml)
        expect(model.name).to eq("bob")
        expect(model.email).to eq("bob@example.com")
        expect(model.tags).to eq(["dev", "test"])
        xml_out = model.to_xml
        expect(xml_out).to include("<name>BOB</name>")
        expect(xml_out).to include("<email>user:bob@example.com</email>")
        expect(xml_out).to include("<tags>Dev</tags>")
        expect(xml_out).to include("<tags>Test</tags>")
      end

      it "handles round-trip transformation for string types" do
        model = described_class.from_json(json)
        json_out = model.to_json
        model2 = described_class.from_json(json_out)
        expect(model2.name).to eq("ALICE")
        expect(model2.email).to eq("alice@example.com")
        expect(model2.tags).to eq(["ruby", "rails"])
      end
    end

    describe TransformationSpec::CombinedTransformModel do
      let(:json) { '{"title": "hello:SUFFIX"}' }
      let(:xml) do
        <<~XML
          <CombinedTransformModel>
            <title>world:SUFFIX</title>
          </CombinedTransformModel>
        XML
      end

      it "applies both attribute and mapping transformations in correct order for JSON" do
        # Input order: mapping transformer first, then attribute transformer
        # "hello:SUFFIX" -> SuffixTransformer.from_json -> "hello" -> PrefixTransformer.from_json -> "hello"
        model = described_class.from_json(json)
        expect(model.title).to eq("hello")

        # Output order: attribute transformer first, then mapping transformer
        # "hello" -> PrefixTransformer.to_json -> "PREFIX:hello" -> SuffixTransformer.to_json -> "PREFIX:hello:SUFFIX"
        json_out = model.to_json
        parsed = JSON.parse(json_out)
        expect(parsed["title"]).to eq("PREFIX:hello:SUFFIX")
      end

      it "applies both attribute and mapping transformations in correct order for XML" do
        # Input order: mapping transformer first, then attribute transformer
        model = described_class.from_xml(xml)
        expect(model.title).to eq("world")

        # Output order: attribute transformer first, then mapping transformer
        xml_out = model.to_xml
        expect(xml_out).to include("<title>PREFIX:world:SUFFIX</title>")
      end

      it "handles round-trip transformation with both transformers" do
        model = described_class.from_json(json)
        json_out = model.to_json
        model2 = described_class.from_json(json_out)
        # Round trip: "hello:SUFFIX" -> "hello" -> "PREFIX:hello:SUFFIX" -> "hello"
        expect(model2.title).to eq("hello")
      end
    end
  end
end
