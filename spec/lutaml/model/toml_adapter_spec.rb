require "spec_helper"
# require "lutaml/model/toml_adapter/toml_rb_adapter"
# require "lutaml/model/toml_adapter/tomlib_adapter"
require_relative "../../fixtures/sample_model"

RSpec.describe "TomlAdapter" do
  shared_examples "a TOML adapter" do |adapter_class|
    let(:attributes) { { name: "John Doe", age: 30 } }
    let(:model) { SampleModel.new(attributes) }

    let(:expected_toml) do
      if adapter_class == Lutaml::Model::Toml::TomlRbAdapter
        TomlRB.dump(attributes)
      elsif adapter_class == Lutaml::Model::Toml::TomlibAdapter
        Tomlib.dump(attributes)
      end
    end

    it "serializes to TOML" do
      toml = adapter_class.new(attributes).to_toml

      expect(toml).to eq(expected_toml)
    end

    it "deserializes from TOML" do
      doc = adapter_class.parse(expected_toml)
      new_model = SampleModel.new(doc.to_h)

      expect(new_model.name).to eq("John Doe")
      expect(new_model.age).to eq(30)
    end
  end

  describe Lutaml::Model::Toml::TomlRbAdapter do
    it_behaves_like "a TOML adapter", described_class
  end

  describe Lutaml::Model::Toml::TomlibAdapter do
    it_behaves_like "a TOML adapter", described_class
  end
end
