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
        {
          "JsonSchemaSpec_Shape" => <<~RUBY.strip,
            require "lutaml/model"

            module JsonSchemaSpec
              class Shape < Lutaml::Model::Serializable
                attribute :area, :float
              end
            end
          RUBY

          "JsonSchemaSpec_Circle" => <<~RUBY.strip,
            require "lutaml/model"

            module JsonSchemaSpec
              class Circle < JsonSchemaSpec::Shape
                attribute :radius, :float
              end
            end
          RUBY

          "JsonSchemaSpec_Square" => <<~RUBY.strip,
            require "lutaml/model"

            module JsonSchemaSpec
              class Square < JsonSchemaSpec::Shape
                attribute :side, :float
              end
            end
          RUBY

          "JsonSchemaSpec_PolymorphicModel" => <<~RUBY.strip,
            require "lutaml/model"

            module JsonSchemaSpec
              class PolymorphicModel < Lutaml::Model::Serializable
                attribute :shape, JsonSchemaSpec::Shape, polymorphic: [JsonSchemaSpec::Circle, JsonSchemaSpec::Square]
              end
            end
          RUBY
        }
      end

      it "generates Ruby model classes with polymorphic types from schema" do
        generated = described_class.generate_model_classes(schema)
        expect(generated.transform_values(&:strip)).to eq(expected_classes)
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
        {
          "JsonSchemaSpec_Detail" => <<~RUBY.strip,
            require "lutaml/model"

            module JsonSchemaSpec
              class Detail < Lutaml::Model::Serializable
                attribute :weight, :float
                attribute :color, :string
              end
            end
          RUBY

          "JsonSchemaSpec_Item" => <<~RUBY.strip,
            require "lutaml/model"

            module JsonSchemaSpec
              class Item < Lutaml::Model::Serializable
                attribute :name, :string
                attribute :detail, JsonSchemaSpec::Detail
              end
            end
          RUBY

          "JsonSchemaSpec_Box" => <<~RUBY.strip,
            require "lutaml/model"

            module JsonSchemaSpec
              class Box < Lutaml::Model::Serializable
                attribute :size, :string
                attribute :items, JsonSchemaSpec::Item, collection: true
              end
            end
          RUBY

          "JsonSchemaSpec_Container" => <<~RUBY.strip,
            require "lutaml/model"

            module JsonSchemaSpec
              class Container < Lutaml::Model::Serializable
                attribute :id, :string
                attribute :box, JsonSchemaSpec::Box
              end
            end
          RUBY
        }
      end

      it "generates Ruby model classes for deeply nested classes from schema" do
        generated = described_class.generate_model_classes(schema)
        expect(generated.transform_values(&:strip)).to eq(expected_classes)
      end
    end
  end
end
