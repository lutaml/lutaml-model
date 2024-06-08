# spec/ceramic_spec.rb
require "spec_helper"
require_relative "fixtures/ceramic"
require_relative "fixtures/glaze"

RSpec.describe Ceramic do
  let(:yaml_data) {
    <<~YAML
      type: Vase
      color: Blue
      finish: Glossy
    YAML
  }

  let(:ceramic) { Ceramic.from_yaml(yaml_data) }

  it "deserializes from YAML with delegation" do
    expect(ceramic.type).to eq("Vase")
    expect(ceramic.glaze.color).to eq("Blue")
    expect(ceramic.glaze.finish).to eq("Glossy")
  end

  it "serializes to YAML with delegation" do
    expected_yaml = <<~YAML
      type: Vase
      color: Blue
      finish: Glossy
    YAML
    expect(ceramic.to_yaml.strip).to eq(expected_yaml.strip)
  end
end
