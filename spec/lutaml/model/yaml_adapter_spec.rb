# spec/lutaml/model/yaml_adapter_spec.rb
require "spec_helper"
require "lutaml/model/yaml_adapter"
require_relative "../fixtures/sample_model"

RSpec.describe Lutaml::Model::YamlAdapter::Standard do
  let(:attributes) { { name: "John Doe", age: 30 } }
  let(:model) { SampleModel.new(attributes) }

  it "serializes to YAML" do
    yaml = described_class.to_yaml(model)
    expect(yaml).to eq(attributes.to_yaml)
  end

  it "deserializes from YAML" do
    yaml = attributes.to_yaml
    new_model = described_class.from_yaml(yaml, SampleModel)
    expect(new_model.name).to eq("John Doe")
    expect(new_model.age).to eq(30)
  end
end
