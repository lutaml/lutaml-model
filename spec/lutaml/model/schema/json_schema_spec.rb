# spec/schema/json_schema_spec.rb
require "spec_helper"
require_relative "../../../fixtures/vase"
require "lutaml/model/schema"

RSpec.describe Lutaml::Model::Schema::JsonSchema do
  it "generates JSON schema for Vase class" do
    schema_json = described_class.generate(
      Vase,
      id: "https://example.org/schema/vase/1.0",
      description: "Vase schema",
      pretty: true,
    )

    expected_json = <<~JSON
      {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://example.org/schema/vase/1.0",
        "description": "Vase schema",
        "$ref": "#/$defs/Vase",
        "$defs": {
          "Vase": {
            "type": "object",
            "properties": {
              "height": {
                "type": "number"
              },
              "diameter": {
                "type": "number"
              },
              "material": {
                "type": "string"
              },
              "manufacturer": {
                "type": "string"
              }
            },
            "required": ["height", "diameter", "material", "manufacturer"]
          }
        }
      }
    JSON

    expect(JSON.parse(schema_json)).to eq(JSON.parse(expected_json))
  end
end
