require "spec_helper"
require "lutaml/model/schema"

module JsonSchemaSpec
  # Class for register testing
  class RegisterGlaze < Lutaml::Model::Serializable
    attribute :color, :string
    attribute :finish, :integer
  end

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

  # For deeply nested classes
  class Detail < Lutaml::Model::Serializable
    attribute :weight, Lutaml::Model::Type::Float
    attribute :color, Lutaml::Model::Type::String
  end

  class Item < Lutaml::Model::Serializable
    attribute :name, Lutaml::Model::Type::String
    attribute :detail, Detail
  end

  class Box < Lutaml::Model::Serializable
    attribute :size, Lutaml::Model::Type::String
    attribute :items, Item, collection: true
  end

  class Container < Lutaml::Model::Serializable
    attribute :id, Lutaml::Model::Type::String
    attribute :box, Box
  end
end

RSpec.describe Lutaml::Model::Schema::JsonSchema do
  describe ".generate" do
    let(:parsed_schema) { JSON.parse(schema) }

    context "with basic model" do
      let(:schema) do
        described_class.generate(
          JsonSchemaSpec::Vase,
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
          "$ref" => "#/$defs/JsonSchemaSpec_Vase",
          "$defs" => {
            "JsonSchemaSpec_Vase" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "height" => {
                  "type" => ["number", "null"],
                },
                "diameter" => {
                  "type" => ["number", "null"],
                },
                "glaze" => {
                  "$ref" => "#/$defs/JsonSchemaSpec_Glaze",
                },
                "materials" => {
                  "type" => "array",
                  "items" => {
                    "type" => "string",
                  },
                },
              },
            },
            "JsonSchemaSpec_Glaze" => {
              "type" => "object",
              "additionalProperties" => false,
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
        described_class.generate(JsonSchemaSpec::ChoiceModel, pretty: true)
      end

      let(:expected_schema) do
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "$ref" => "#/$defs/JsonSchemaSpec_ChoiceModel",
          "$defs" => {
            "JsonSchemaSpec_ChoiceModel" => {
              "type" => "object",
              "additionalProperties" => false,
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
          JsonSchemaSpec::ValidationModel,
          pretty: true,
        )
      end

      let(:expected_schema) do
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "$ref" => "#/$defs/JsonSchemaSpec_ValidationModel",
          "$defs" => {
            "JsonSchemaSpec_ValidationModel" => {
              "type" => "object",
              "additionalProperties" => false,
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
          JsonSchemaSpec::PolymorphicModel,
          pretty: true,
        )
      end

      let(:expected_schema) do
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "$ref" => "#/$defs/JsonSchemaSpec_PolymorphicModel",
          "$defs" => {
            "JsonSchemaSpec_PolymorphicModel" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "shape" => {
                  "type" => ["object", "null"],
                  "oneOf" => [
                    {
                      "$ref" => "#/$defs/JsonSchemaSpec_Circle",
                    },
                    {
                      "$ref" => "#/$defs/JsonSchemaSpec_Square",
                    },
                    {
                      "$ref" => "#/$defs/JsonSchemaSpec_Shape",
                    },
                  ],
                },
              },
            },
            "JsonSchemaSpec_Circle" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "area" => {
                  "type" => ["number", "null"],
                },
                "radius" => {
                  "type" => ["number", "null"],
                },
              },
            },
            "JsonSchemaSpec_Square" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "area" => {
                  "type" => ["number", "null"],
                },
                "side" => {
                  "type" => ["number", "null"],
                },
              },
            },
            "JsonSchemaSpec_Shape" => {
              "type" => "object",
              "additionalProperties" => false,
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

    context "with deeply nested classes" do
      let(:schema) do
        described_class.generate(
          JsonSchemaSpec::Container,
          pretty: true,
        )
      end

      let(:expected_schema) do
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "$ref" => "#/$defs/JsonSchemaSpec_Container",
          "$defs" => {
            "JsonSchemaSpec_Container" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "id" => {
                  "type" => ["string", "null"],
                },
                "box" => {
                  "$ref" => "#/$defs/JsonSchemaSpec_Box",
                },
              },
            },
            "JsonSchemaSpec_Box" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "size" => {
                  "type" => ["string", "null"],
                },
                "items" => {
                  "type" => "array",
                  "items" => {
                    "$ref" => "#/$defs/JsonSchemaSpec_Item",
                  },
                },
              },
            },
            "JsonSchemaSpec_Item" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "name" => {
                  "type" => ["string", "null"],
                },
                "detail" => {
                  "$ref" => "#/$defs/JsonSchemaSpec_Detail",
                },
              },
            },
            "JsonSchemaSpec_Detail" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "weight" => {
                  "type" => ["number", "null"],
                },
                "color" => {
                  "type" => ["string", "null"],
                },
              },
            },
          },
        }
      end

      it "generates a JSON schema for deeply nested classes" do
        expect(parsed_schema).to eq(expected_schema)
      end
    end

    context "with register class" do
      let(:register) { Lutaml::Model::Register.new(:json_schema) }
      let(:schema) { described_class.generate(register.get_class(:vase), pretty: true) }
      let(:expected_schema) do
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "$ref" => "#/$defs/JsonSchemaSpec_Vase",
          "$defs" => {
            "JsonSchemaSpec_Vase" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "height" => {
                  "type" => ["number", "null"],
                },
                "diameter" => {
                  "type" => ["number", "null"],
                },
                "glaze" => {
                  "$ref" => "#/$defs/JsonSchemaSpec_RegisterGlaze",
                },
                "materials" => {
                  "type" => "array",
                  "items" => {
                    "type" => "string",
                  },
                },
              },
            },
            "JsonSchemaSpec_RegisterGlaze" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "color" => {
                  "type" => ["string", "null"],
                },
                "finish" => {
                  "type" => ["integer", "null"],
                },
              },
            },
          },
        }
      end

      before do
        Lutaml::Model::GlobalRegister.register(register)
        register.register_model_tree(JsonSchemaSpec::Vase)
        register.register_global_type_substitution(
          from_type: JsonSchemaSpec::Glaze,
          to_type: JsonSchemaSpec::RegisterGlaze,
        )
      end

      it "generates a JSON schema with substituted registered class" do
        expect(parsed_schema).to eq(expected_schema)
      end
    end
  end
end
