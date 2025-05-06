require "spec_helper"
require "lutaml/model/schema"

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

  class ChoiceModel < Lutaml::Model::Serializable
    attribute :name, Lutaml::Model::Type::String
    attribute :email, Lutaml::Model::Type::String
    attribute :phone, Lutaml::Model::Type::String

    choice(min: 1, max: 2) do
      attribute :email, Lutaml::Model::Type::String
      attribute :phone, Lutaml::Model::Type::String
    end
  end

  class ValidationModel < Lutaml::Model::Serializable
    attribute :name, Lutaml::Model::Type::String, values: %w[Alice Bob Charlie]
    attribute :email, Lutaml::Model::Type::String, pattern: /.*?\S+@.+\.\S+/
    attribute :age, Lutaml::Model::Type::Integer, collection: 1..3
    attribute :score, Lutaml::Model::Type::Float, default: 0.0
  end

  class Shape < Lutaml::Model::Serializable
    attribute :area, :float
  end

  class Circle < Shape
    attribute :radius, Lutaml::Model::Type::Float
  end

  class Square < Shape
    attribute :side, Lutaml::Model::Type::Float
  end

  class PolymorphicModel < Lutaml::Model::Serializable
    attribute :shape, Shape, polymorphic: [Circle, Square]
  end
end

RSpec.describe Lutaml::Model::Schema::JsonSchema do
  describe ".generate" do
    let(:parsed_schema) { JSON.parse(schema) }

    context "with basic model" do
      let(:schema) do
        described_class.generate(
          SchemaGeneration::Vase,
          id: "https://example.com/vase.schema.json",
          description: "A vase schema",
          pretty: true,
        )
      end

      let(:expected_schema) do
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "$id" => "https://example.com/vase.schema.json",
          "description" => "A vase schema",
          "$ref" => "#/$defs/SchemaGeneration::Vase",
          "$defs" => {
            "SchemaGeneration::Vase" => {
              "type" => "object",
              "properties" => {
                "height" => {
                  "type" => ["number", "null"],
                },
                "diameter" => {
                  "type" => ["number", "null"],
                },
                "glaze" => {
                  "$ref" => "#/$defs/SchemaGeneration::Glaze",
                },
                "materials" => {
                  "type" => "array",
                  "items" => {
                    "type" => "string",
                  },
                },
              },
            },
            "SchemaGeneration::Glaze" => {
              "type" => "object",
              "properties" => {
                "color" => {
                  "type" => ["string", "null"],
                },
                "finish" => {
                  "type" => ["string", "null"],
                },
              },
            },
          },
        }
      end

      it "generates a JSON schema for nested Serialize objects" do
        expect(parsed_schema).to eq(expected_schema)
      end
    end

    context "with choice validation" do
      let(:schema) do
        described_class.generate(SchemaGeneration::ChoiceModel, pretty: true)
      end

      let(:expected_schema) do
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "$ref" => "#/$defs/SchemaGeneration::ChoiceModel",
          "$defs" => {
            "SchemaGeneration::ChoiceModel" => {
              "type" => "object",
              "properties" => {
                "name" => {
                  "type" => ["string", "null"],
                },
                "email" => {
                  "type" => ["string", "null"],
                },
                "phone" => {
                  "type" => ["string", "null"],
                },
              },
              "oneOf" => [
                {
                  "type" => "object",
                  "properties" => {
                    "email" => {
                      "type" => ["string", "null"],
                    },
                    "phone" => {
                      "type" => ["string", "null"],
                    },
                  },
                  "minProperties" => 1,
                  "maxProperties" => 2,
                },
              ],
            },
          },
        }
      end

      it "generates a JSON schema with choice constraints" do
        expect(parsed_schema).to eq(expected_schema)
      end
    end

    context "with validation constraints" do
      let(:schema) do
        described_class.generate(
          SchemaGeneration::ValidationModel,
          pretty: true,
        )
      end

      let(:expected_schema) do
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "$ref" => "#/$defs/SchemaGeneration::ValidationModel",
          "$defs" => {
            "SchemaGeneration::ValidationModel" => {
              "type" => "object",
              "properties" => {
                "name" => {
                  "type" => ["string", "null"],
                  "enum" => ["Alice", "Bob", "Charlie"],
                },
                "email" => {
                  "type" => ["string", "null"],
                  "pattern" => ".*?\\S+@.+\\.\\S+",
                },
                "age" => {
                  "type" => "array",
                  "items" => {
                    "type" => "integer",
                  },
                  "minItems" => 1,
                  "maxItems" => 3,
                },
                "score" => {
                  "type" => ["number", "null"],
                  "default" => 0.0,
                },
              },
            },
          },
        }
      end

      it "generates a JSON schema with validation constraints" do
        expect(parsed_schema).to eq(expected_schema)
      end
    end

    context "with polymorphic types" do
      let(:schema) do
        described_class.generate(
          SchemaGeneration::PolymorphicModel,
          pretty: true,
        )
      end

      let(:expected_schema) do
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "$ref" => "#/$defs/SchemaGeneration::PolymorphicModel",
          "$defs" => {
            "SchemaGeneration::PolymorphicModel" => {
              "type" => "object",
              "properties" => {
                "shape" => {
                  "type" => ["object", "null"],
                  "oneOf" => [
                    {
                      "$ref" => "#/$defs/SchemaGeneration::Circle",
                    },
                    {
                      "$ref" => "#/$defs/SchemaGeneration::Square",
                    },
                  ],
                },
              },
            },
            "SchemaGeneration::Circle" => {
              "allOf" => [
                { "$ref" => "#/$defs/SchemaGeneration::Shape" },
                {
                  "type" => "object",
                  "properties" => {
                    "radius" => {
                      "type" => ["number", "null"],
                    },
                  },
                },
              ],
            },
            "SchemaGeneration::Square" => {
              "allOf" => [
                { "$ref" => "#/$defs/SchemaGeneration::Shape" },
                {
                  "type" => "object",
                  "properties" => {
                    "side" => {
                      "type" => ["number", "null"],
                    },
                  },
                },
              ],
            },
            "SchemaGeneration::Shape" => {
              "type" => "object",
              "properties" => {
                "area" => { "type" => ["number", "null"] },
              },
            },
          },
        }
      end

      it "generates a JSON schema with polymorphic type constraints" do
        expect(parsed_schema).to eq(expected_schema)
      end
    end
  end

  describe ".generate_properties" do
    let(:properties) do
      described_class.generate_properties(SchemaGeneration::Vase)
    end

    let(:expected_propertied) do
      %i[height diameter glaze materials]
    end

    it "returns only non-inherited properties" do
      expect(properties.keys).to match_array(expected_propertied)
    end
  end

  describe ".generate_property_schema" do
    context "with collection attribute" do
      let(:attr) { SchemaGeneration::Vase.attributes[:materials] }

      it "generates array schema with items type" do
        schema = described_class.generate_property_schema(attr)
        expect(schema).to eq({
                               "type" => "array",
                               "items" => { "type" => "string" },
                             })
      end
    end

    context "with serializable attribute" do
      let(:attr) { SchemaGeneration::Vase.attributes[:glaze] }

      it "generates reference schema" do
        schema = described_class.generate_property_schema(attr)
        expect(schema).to eq({
                               "$ref" => "#/$defs/SchemaGeneration::Glaze",
                             })
      end
    end

    context "with polymorphic attribute" do
      let(:attr) { SchemaGeneration::PolymorphicModel.attributes[:shape] }

      let(:expected_schema) do
        {
          "type" => ["object", "null"],
          "oneOf" => [
            { "$ref" => "#/$defs/SchemaGeneration::Circle" },
            { "$ref" => "#/$defs/SchemaGeneration::Square" },
          ],
        }
      end

      it "generates polymorphic schema" do
        schema = described_class.generate_property_schema(attr)
        expect(schema).to eq(expected_schema)
      end
    end

    context "with primitive attribute" do
      let(:attr) { SchemaGeneration::Vase.attributes[:height] }

      it "generates primitive schema with constraints" do
        schema = described_class.generate_property_schema(attr)
        expect(schema).to eq({ "type" => ["number", "null"] })
      end
    end
  end

  describe ".collection_schema" do
    let(:attr) { SchemaGeneration::Vase.attributes[:materials] }

    it "generates array schema with items" do
      schema = described_class.collection_schema(attr)
      expect(schema).to eq({
                             "type" => "array",
                             "items" => { "type" => "string" },
                           })
    end

    context "with range constraint" do
      let(:attr) { SchemaGeneration::ValidationModel.attributes[:age] }
      let(:expected_schema) do
        {
          "type" => "array",
          "items" => { "type" => "integer" },
          "minItems" => 1,
          "maxItems" => 3,
        }
      end

      it "adds min and max items constraints" do
        schema = described_class.collection_schema(attr)
        expect(schema).to eq(expected_schema)
      end
    end
  end

  describe ".collection_items_schema" do
    let(:schema) { described_class.collection_items_schema(attr) }

    context "with serializable items" do
      let(:attr) { SchemaGeneration::Vase.attributes[:glaze] }

      it "returns reference schema" do
        expect(schema).to eq({ "$ref" => "#/$defs/SchemaGeneration::Glaze" })
      end
    end

    context "with primitive items" do
      let(:attr) { SchemaGeneration::Vase.attributes[:materials] }

      it "returns type schema" do
        expect(schema).to eq({ "type" => "string" })
      end
    end
  end

  describe ".polymorphic_schema" do
    let(:attr) { SchemaGeneration::PolymorphicModel.attributes[:shape] }
    let(:expected_schema) do
      {
        "type" => ["object", "null"],
        "oneOf" => [
          { "$ref" => "#/$defs/SchemaGeneration::Circle" },
          { "$ref" => "#/$defs/SchemaGeneration::Square" },
        ],
      }
    end

    it "generates schema with oneOf references" do
      schema = described_class.polymorphic_schema(attr)
      expect(schema).to eq(expected_schema)
    end
  end

  describe ".reference_schema" do
    let(:attr) { SchemaGeneration::Vase.attributes[:glaze] }

    it "generates reference to type definition" do
      schema = described_class.reference_schema(attr)
      expect(schema).to eq({ "$ref" => "#/$defs/SchemaGeneration::Glaze" })
    end
  end

  describe ".primitive_schema" do
    let(:attr) { SchemaGeneration::Vase.attributes[:height] }

    it "generates schema with type and constraints" do
      schema = described_class.primitive_schema(attr)
      expect(schema).to eq({ "type" => ["number", "null"] })
    end

    context "with pattern" do
      let(:attr) { SchemaGeneration::ValidationModel.attributes[:email] }

      it "includes pattern constraint" do
        schema = described_class.primitive_schema(attr)
        expect(schema["pattern"]).to eq(".*?\\S+@.+\\.\\S+")
      end
    end

    context "with enum" do
      let(:attr) { SchemaGeneration::ValidationModel.attributes[:name] }

      it "includes enum constraint" do
        schema = described_class.primitive_schema(attr)
        expect(schema["enum"]).to eq(["Alice", "Bob", "Charlie"])
      end
    end
  end

  describe ".add_collection_constraints!" do
    let(:schema) { { "type" => "array" } }
    let(:range) { 1..3 }

    let(:expected_schema) do
      {
        "type" => "array",
        "minItems" => 1,
        "maxItems" => 3,
      }
    end

    it "adds min and max items" do
      described_class.add_collection_constraints!(schema, range)
      expect(schema).to eq(expected_schema)
    end
  end

  describe ".serializable?" do
    it "returns true for serializable types" do
      attr = SchemaGeneration::Vase.attributes[:glaze]
      expect(described_class.serializable?(attr)).to be true
    end

    it "returns false for primitive types" do
      attr = SchemaGeneration::Vase.attributes[:height]
      expect(described_class.serializable?(attr)).to be false
    end
  end

  describe ".polymorphic?" do
    it "returns true for polymorphic attributes" do
      attr = SchemaGeneration::PolymorphicModel.attributes[:shape]
      expect(described_class.polymorphic?(attr)).to be true
    end

    it "returns false for non-polymorphic attributes" do
      attr = SchemaGeneration::Vase.attributes[:glaze]
      expect(described_class.polymorphic?(attr)).to be false
    end
  end
end
