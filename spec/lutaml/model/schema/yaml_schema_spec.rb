# spec/schema/yaml_schema_spec.rb
require "spec_helper"
require_relative "../../../fixtures/vase"
require "lutaml/model/schema"

RSpec.describe Lutaml::Model::Schema::YamlSchema do
  it "generates YAML schema for Vase class" do
    schema_yaml = described_class.generate(Vase)
    expected_yaml = <<-YAML
---
type: map
mapping:
  height:
    type: float
  diameter:
    type: float
  material:
    type: str
  manufacturer:
    type: str
    YAML

    expect(YAML.load(schema_yaml)).to eq(YAML.load(expected_yaml))
  end
end
