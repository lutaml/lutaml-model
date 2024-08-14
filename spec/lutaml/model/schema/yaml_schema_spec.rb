require "spec_helper"
require_relative "../../../fixtures/vase"
require "lutaml/model/schema"

RSpec.describe Lutaml::Model::Schema::YamlSchema do
  it "generates YAML schema for Vase class" do
    schema_yaml = described_class.generate(Vase)
    expected_yaml = <<~YAML
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

    expect(YAML.safe_load(schema_yaml)).to eq(YAML.safe_load(expected_yaml))
  end
end
