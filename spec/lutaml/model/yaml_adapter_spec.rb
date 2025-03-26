require "spec_helper"
require_relative "../../fixtures/sample_model"

RSpec.shared_examples "a YAML adapter" do |adapter_class|
  let(:attributes) { { "name" => "John Doe", "age" => 30 } }
  let(:model) { SampleModel.new(attributes) }

  let(:expected_yaml) do
    if adapter_class == Lutaml::Model::Yaml::StandardAdapter
      attributes.to_yaml
    end
  end

  it "serializes to YAML" do
    yaml = adapter_class.new(attributes).to_yaml

    expect(yaml).to eq(expected_yaml)
  end

  it "deserializes from YAML" do
    new_model = adapter_class.parse(expected_yaml)
    expect(new_model).to eq(attributes)
  end
end

RSpec.describe Lutaml::Model::Yaml::StandardAdapter do
  it_behaves_like "a YAML adapter", described_class
end
