require "lutaml/model/schema"

RSpec.describe Lutaml::Model::Schema::JsonSchema do
  describe ".generate_model_classes" do
    context "with basic model schema" do
      let(:schema) do
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
                "height" => { "type" => ["number", "null"] },
                "diameter" => { "type" => ["number", "null"] },
                "glaze" => { "$ref" => "#/$defs/JsonSchemaSpec_Glaze" },
                "materials" => {
                  "type" => "array",
                  "items" => { "type" => "string" },
                },
              },
            },
            "JsonSchemaSpec_Glaze" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "color" => { "type" => ["string", "null"] },
                "finish" => { "type" => ["string", "null"] },
              },
            },
          },
        }
      end

      let(:glaze_class) do
        <<~RUBY
          require "lutaml/model"

          module JsonSchemaSpec
            class Glaze < Lutaml::Model::Serializable
              attribute :color, :string
              attribute :finish, :string
            end
          end
        RUBY
      end

      let(:vase_class) do
        <<~RUBY
          require "lutaml/model"

          module JsonSchemaSpec
            class Vase < Lutaml::Model::Serializable
              attribute :height, :float
              attribute :diameter, :float
              attribute :glaze, JsonSchemaSpec::Glaze
              attribute :materials, :string, collection: true
            end
          end
        RUBY
      end

      let(:expected_classes) do
        {
          "JsonSchemaSpec_Glaze" => glaze_class,
          "JsonSchemaSpec_Vase" => vase_class,
        }
        # <<~RUBY
        #   module JsonSchemaSpec
        #     class Glaze < Lutaml::Model::Serializable
        #       attribute :color, Lutaml::Model::Type::String
        #       attribute :finish, Lutaml::Model::Type::String
        #     end
        #   end

        #   module JsonSchemaSpec
        #     class Vase < Lutaml::Model::Serializable
        #       attribute :height, Lutaml::Model::Type::Float
        #       attribute :diameter, Lutaml::Model::Type::Float
        #       attribute :glaze, JsonSchemaSpec_Glaze
        #       attribute :materials, Lutaml::Model::Type::String, collection: true
        #     end
        #   end
        # RUBY
      end

      it "generates Ruby model classes from schema" do
        generated = described_class.generate_model_classes(schema)

        expect(generated["JsonSchemaSpec_Vase"].strip).to eq(vase_class.strip)
        expect(generated["JsonSchemaSpec_Glaze"].strip).to eq(glaze_class.strip)
      end
    end

    context "with choice validation schema" do
      let(:schema) do
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "$ref" => "#/$defs/JsonSchemaSpec_ChoiceModel",
          "$defs" => {
            "JsonSchemaSpec_ChoiceModel" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "name" => { "type" => ["string", "null"] },
                "email" => { "type" => ["string", "null"] },
                "phone" => { "type" => ["string", "null"] },
              },
              "oneOf" => [
                {
                  "type" => "object",
                  "properties" => {
                    "email" => { "type" => ["string", "null"] },
                    "phone" => { "type" => ["string", "null"] },
                  },
                },
              ],
            },
          },
        }
      end

      let(:expected_classes) do
        <<~RUBY
          require "lutaml/model"

          module JsonSchemaSpec
            class ChoiceModel < Lutaml::Model::Serializable
              attribute :name, :string

              choice do
                attribute :email, :string
                attribute :phone, :string
              end
            end
          end
        RUBY
      end

      it "generates Ruby model classes with choice constraints from schema" do
        generated = described_class.generate_model_classes(schema)
        expect(generated["JsonSchemaSpec_ChoiceModel"].strip).to eq(expected_classes.strip)
      end
    end

    context "with validation constraints schema" do
      let(:schema) do
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
                  "items" => { "type" => "integer" },
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

      let(:expected_classes) do
        <<~RUBY
          require "lutaml/model"

          module JsonSchemaSpec
            class ValidationModel < Lutaml::Model::Serializable
              attribute :name, :string, values: ["Alice", "Bob", "Charlie"]
              attribute :email, :string, pattern: /.*?\\S+@.+\\.\\S+/
              attribute :age, :integer, collection: 1..3
              attribute :score, :float, default: 0.0
            end
          end
        RUBY
      end

      it "generates Ruby model classes with validation constraints from schema" do
        generated = described_class.generate_model_classes(schema)
        expect(generated["JsonSchemaSpec_ValidationModel"].strip).to eq(expected_classes.strip)
      end
    end

    context "with polymorphic types schema" do
      let(:schema) do
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
                    { "$ref" => "#/$defs/JsonSchemaSpec_Circle" },
                    { "$ref" => "#/$defs/JsonSchemaSpec_Square" },
                    { "$ref" => "#/$defs/JsonSchemaSpec_Shape" },
                  ],
                },
              },
            },
            "JsonSchemaSpec_Circle" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "area" => { "type" => ["number", "null"] },
                "radius" => { "type" => ["number", "null"] },
              },
            },
            "JsonSchemaSpec_Square" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "area" => { "type" => ["number", "null"] },
                "side" => { "type" => ["number", "null"] },
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

      let(:expected_classes) do
        <<~RUBY
          class JsonSchemaSpec_Shape < Lutaml::Model::Serializable
            attribute :area, :float
          end

          class JsonSchemaSpec_Circle < JsonSchemaSpec_Shape
            attribute :radius, :float
          end

          class JsonSchemaSpec_Square < JsonSchemaSpec_Shape
            attribute :side, :float
          end

          class JsonSchemaSpec_PolymorphicModel < Lutaml::Model::Serializable
            attribute :shape, JsonSchemaSpec::Shape, polymorphic: [JsonSchemaSpec::Circle, JsonSchemaSpec::Square]
          end
        RUBY
      end

      it "generates Ruby model classes with polymorphic types from schema" do
        generated = described_class.generate_model_classes(schema)
        require "pry"
        binding.pry
        expect(generated.strip).to eq(expected_classes.strip)
      end
    end

    context "with deeply nested classes schema" do
      let(:schema) do
        {
          "$schema" => "https://json-schema.org/draft/2020-12/schema",
          "$ref" => "#/$defs/JsonSchemaSpec_Container",
          "$defs" => {
            "JsonSchemaSpec_Container" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "id" => { "type" => ["string", "null"] },
                "box" => { "$ref" => "#/$defs/JsonSchemaSpec_Box" },
              },
            },
            "JsonSchemaSpec_Box" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "size" => { "type" => ["string", "null"] },
                "items" => {
                  "type" => "array",
                  "items" => { "$ref" => "#/$defs/JsonSchemaSpec_Item" },
                },
              },
            },
            "JsonSchemaSpec_Item" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "name" => { "type" => ["string", "null"] },
                "detail" => { "$ref" => "#/$defs/JsonSchemaSpec_Detail" },
              },
            },
            "JsonSchemaSpec_Detail" => {
              "type" => "object",
              "additionalProperties" => false,
              "properties" => {
                "weight" => { "type" => ["number", "null"] },
                "color" => { "type" => ["string", "null"] },
              },
            },
          },
        }
      end

      let(:expected_classes) do
        <<~RUBY
          class JsonSchemaSpec_Detail < Lutaml::Model::Serializable
            attribute :weight, Lutaml::Model::Type::Float
            attribute :color, Lutaml::Model::Type::String
          end

          class JsonSchemaSpec_Item < Lutaml::Model::Serializable
            attribute :name, Lutaml::Model::Type::String
            attribute :detail, JsonSchemaSpec_Detail
          end

          class JsonSchemaSpec_Box < Lutaml::Model::Serializable
            attribute :size, Lutaml::Model::Type::String
            attribute :items, JsonSchemaSpec_Item, collection: true
          end

          class JsonSchemaSpec_Container < Lutaml::Model::Serializable
            attribute :id, Lutaml::Model::Type::String
            attribute :box, JsonSchemaSpec_Box
          end
        RUBY
      end

      it "generates Ruby model classes for deeply nested classes from schema" do
        generated = described_class.generate_model_classes(schema)
        expect(generated.strip).to eq(expected_classes.strip)
      end
    end
  end
end
