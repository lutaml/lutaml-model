# spec/lutaml/model/toml_adapter_spec.rb
require "spec_helper"
require "lutaml/model/toml_adapter/toml_rb_adapter"
require "lutaml/model/toml_adapter/tomlib_adapter"
require_relative "../../fixtures/sample_model"

RSpec.shared_examples "a TOML adapter" do |adapter_class|
  let(:attributes) { { name: "John Doe", age: 30 } }
  let(:model) { SampleModel.new(attributes) }

  it "serializes to TOML" do
    toml = adapter_class.new(attributes).to_toml
    expected_toml = <<~TOML
      age = 30
      name = "John Doe"
    TOML

    expect(toml).to eq(expected_toml)
  end

  it "deserializes from TOML" do
    toml = adapter_class == Lutaml::Model::TomlAdapter::TomlRbDocument ? TomlRB.dump(attributes) : Tomlib::Generator.new(attributes).toml_str
    doc = adapter_class.parse(toml)
    new_model = SampleModel.new(doc.to_h)
    expect(new_model.name).to eq("John Doe")
    expect(new_model.age).to eq(30)
  end
end

RSpec.describe Lutaml::Model::TomlAdapter::TomlRbDocument do
  it_behaves_like "a TOML adapter", described_class
end

RSpec.describe Lutaml::Model::TomlAdapter::TomlibDocument do
  it_behaves_like "a TOML adapter", described_class
end
