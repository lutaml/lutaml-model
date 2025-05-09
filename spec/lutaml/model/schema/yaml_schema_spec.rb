require "spec_helper"
require "lutaml/model/schema"

module YamlSchemaSpec
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

RSpec.describe Lutaml::Model::Schema::YamlSchema do
  describe ".generate" do
    context "with basic model" do
      let(:schema) do
        described_class.generate(
          YamlSchemaSpec::Vase,
          id: "http://stsci.edu/schemas/yaml-schema/draft-01",
          description: "A vase schema",
        )
      end

      let(:expected_schema) do
        <<~YAML
          %YAML 1.1
          ---
          "$schema": https://json-schema.org/draft/2020-12/schema
          "$id": http://stsci.edu/schemas/yaml-schema/draft-01
          description: A vase schema
          "$ref": "#/$defs/YamlSchemaSpec_Vase"
          "$defs":
            YamlSchemaSpec_Vase:
              type: object
              additionalProperties: false
              properties:
                height:
                  type:
                  - number
                  - 'null'
                diameter:
                  type:
                  - number
                  - 'null'
                glaze:
                  "$ref": "#/$defs/YamlSchemaSpec_Glaze"
                materials:
                  type: array
                  items:
                    type: string
            YamlSchemaSpec_Glaze:
              type: object
              additionalProperties: false
              properties:
                color:
                  type:
                  - string
                  - 'null'
                finish:
                  type:
                  - string
                  - 'null'

        YAML
      end

      it "generates a YAML schema for nested Serialize objects" do
        expect(schema).to eq(expected_schema)
      end
    end

    context "with choice validation" do
      let(:schema) do
        described_class.generate(YamlSchemaSpec::ChoiceModel)
      end

      let(:expected_schema) do
        <<~YAML
          %YAML 1.1
          ---
          "$schema": https://json-schema.org/draft/2020-12/schema
          "$ref": "#/$defs/YamlSchemaSpec_ChoiceModel"
          "$defs":
            YamlSchemaSpec_ChoiceModel:
              type: object
              additionalProperties: false
              properties:
                name:
                  type:
                  - string
                  - 'null'
                email:
                  type:
                  - string
                  - 'null'
                phone:
                  type:
                  - string
                  - 'null'
              oneOf:
              - type: object
                properties:
                  email:
                    type:
                    - string
                    - 'null'
                  phone:
                    type:
                    - string
                    - 'null'
        YAML
      end

      it "generates a YAML schema with choice constraints" do
        expect(schema.strip).to eq(expected_schema.strip)
      end
    end

    context "with validation constraints" do
      let(:schema) do
        described_class.generate(YamlSchemaSpec::ValidationModel)
      end

      let(:expected_schema) do
        <<~YAML
          %YAML 1.1
          ---
          "$schema": https://json-schema.org/draft/2020-12/schema
          "$ref": "#/$defs/YamlSchemaSpec_ValidationModel"
          "$defs":
            YamlSchemaSpec_ValidationModel:
              type: object
              additionalProperties: false
              properties:
                name:
                  type:
                  - string
                  - 'null'
                  enum:
                  - Alice
                  - Bob
                  - Charlie
                email:
                  type:
                  - string
                  - 'null'
                  pattern: ".*?\\\\S+@.+\\\\.\\\\S+"
                age:
                  type: array
                  items:
                    type: integer
                  minItems: 1
                  maxItems: 3
                score:
                  type:
                  - number
                  - 'null'
                  default: 0.0
        YAML
      end

      it "generates a YAML schema with validation constraints" do
        expect(schema.strip).to eq(expected_schema.strip)
      end
    end

    context "with polymorphic types" do
      let(:schema) do
        described_class.generate(YamlSchemaSpec::PolymorphicModel)
      end

      let(:expected_schema) do
        <<~YAML
          %YAML 1.1
          ---
          "$schema": https://json-schema.org/draft/2020-12/schema
          "$ref": "#/$defs/YamlSchemaSpec_PolymorphicModel"
          "$defs":
            YamlSchemaSpec_PolymorphicModel:
              type: object
              additionalProperties: false
              properties:
                shape:
                  type:
                  - object
                  - 'null'
                  oneOf:
                  - "$ref": "#/$defs/YamlSchemaSpec_Circle"
                  - "$ref": "#/$defs/YamlSchemaSpec_Square"
                  - "$ref": "#/$defs/YamlSchemaSpec_Shape"
            YamlSchemaSpec_Shape:
              type: object
              additionalProperties: false
              properties:
                area:
                  type:
                  - number
                  - 'null'
            YamlSchemaSpec_Circle:
              type: object
              additionalProperties: false
              properties:
                area:
                  type:
                  - number
                  - 'null'
                radius:
                  type:
                  - number
                  - 'null'
            YamlSchemaSpec_Square:
              type: object
              additionalProperties: false
              properties:
                area:
                  type:
                  - number
                  - 'null'
                side:
                  type:
                  - number
                  - 'null'
        YAML
      end

      it "generates a YAML schema with polymorphic type constraints" do
        expect(schema.strip).to eq(expected_schema.strip)
      end
    end
  end
end
