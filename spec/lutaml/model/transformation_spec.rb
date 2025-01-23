require "spec_helper"

RSpec.describe "Value Transformations" do
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
        export: lambda(&:downcase),
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
        map_element "contact-email", to: :email, transform: {
          export: ->(value) { "contact+#{value}" },
          import: ->(value) { value.gsub("contact+", "") },
        }
        map_element "skills", to: :tags
      end
    end
  end

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

    it "applies mapping transformations during JSON deserialization" do
      json = {
        "fullName" => "Dr. bob",
        "emailAddress" => "bobattest.com",
        "labels" => "senior|lead",
      }.to_json

      parsed = TransformationSpec::MappingTransformPerson.from_json(json)
      expect(parsed.name).to eq("Dr. bob")
      expect(parsed.email).to eq("bob@test.com")
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
        <person>
          <full-name>Prof. carol</full-name>
          <contact-email>contact+CAROL@TEST.COM</contact-email>
          <skills>MANAGER-1</skills>
          <skills>AGILE-1</skills>
        </person>
      XML
    end

    it "applies both transformations with correct precedence in JSON" do
      json = combined_person.to_json
      parsed = JSON.parse(json)

      expect(parsed["fullName"]).to eq("Prof. carol")
      expect(parsed["contactEmail"]).to eq("contact+CAROL@TEST.COM")
    end

    it "handles round-trip transformations across formats" do
      # JSON -> Key-Value -> JSON cycle
      json = combined_person.to_json
      parsed_json = TransformationSpec::CombinedTransformPerson.from_json(json)
      expect(parsed_json.name).to eq("carol")
      expect(parsed_json.email).to eq("CAROL@TEST.COM")
      expect(parsed_json.tags).to eq(["MANAGER-1", "AGILE-1"])
    end

    it "applies both transformations with correct precedence in XML" do
      xml = combined_person.to_xml
      parsed_xml = TransformationSpec::CombinedTransformPerson.from_xml(xml)
      expect(parsed_xml.to_xml).to be_equivalent_to(expected_xml)
    end
  end
end
