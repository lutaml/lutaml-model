require "spec_helper"
require "lutaml/model/json/standard_adapter"
require "lutaml/model/json/multi_json_adapter"
require "lutaml/model/json/oj_adapter"
require_relative "../../fixtures/sample_model"

RSpec.describe "JsonAdapter" do
  shared_examples "a JSON adapter" do |adapter_class|
    let(:attributes) { { name: "John Doe", age: 30 } }
    let(:model) { SampleModel.new(attributes) }

    let(:expected_json) do
      if adapter_class == Lutaml::Model::Json::StandardAdapter
        JSON.generate(attributes)
      elsif adapter_class == Lutaml::Model::Json::MultiJsonAdapter
        MultiJson.dump(attributes)
      elsif adapter_class == Lutaml::Model::Json::OjAdapter
        Oj.dump(attributes)
      end
    end

    it "serializes to JSON" do
      json = adapter_class.new(attributes).to_json
      expect(json).to eq(expected_json)
    end

    it "deserializes from JSON" do
      doc = adapter_class.parse(expected_json)
      new_model = SampleModel.new(doc.to_h)
      expect(new_model.name).to eq("John Doe")
      expect(new_model.age).to eq(30)
    end
  end

  describe Lutaml::Model::Json::StandardAdapter do
    it_behaves_like "a JSON adapter", described_class
  end

  describe Lutaml::Model::Json::MultiJsonAdapter do
    it_behaves_like "a JSON adapter", described_class
  end

  describe Lutaml::Model::Json::OjAdapter do
    it_behaves_like "a JSON adapter", described_class
  end
end
