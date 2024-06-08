# spec/schema_spec.rb
require "spec_helper"
require_relative "fixtures/ceramic"
require "lutaml/model/schema"

RSpec.describe Lutaml::Model::Schema do
  it "generates JSON schema for Ceramic class" do
    schema_json = Lutaml::Model::Schema.to_json(Ceramic, id: "https://example.org/schema/ceramic/1.1", description: "Ceramic schema", pretty: true)

    expected_json = <<-JSON
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://example.org/schema/ceramic/1.1",
  "description": "Ceramic schema",
  "$ref": "#/$defs/Ceramic",
  "$defs": {
    "Ceramic": {
      "type": "object",
      "properties": {
        "type": {
          "type": "string"
        },
        "glaze": {
          "type": "object"
        },
        "date": {
          "type": "string"
        }
      },
      "required": ["type", "glaze", "date"]
    }
  }
}
    JSON

    expect(JSON.parse(schema_json)).to eq(JSON.parse(expected_json))
  end
end
