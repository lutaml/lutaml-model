require "spec_helper"
require "lutaml/key_value/adapter/json/standard_adapter"
require "lutaml/key_value/adapter/json/multi_json_adapter"
require "lutaml/key_value/adapter/json/oj_adapter"
require_relative "../../fixtures/sample_model"

RSpec.describe "JsonAdapter" do
  shared_examples "a JSON adapter" do |adapter_class|
    let(:attributes) { { name: "John Doe", age: 30 } }
    let(:model) { SampleModel.new(attributes) }

    let(:expected_json) do
      if adapter_class == Lutaml::KeyValue::Adapter::Json::StandardAdapter
        JSON.generate(attributes)
      elsif adapter_class == Lutaml::KeyValue::Adapter::Json::MultiJsonAdapter
        MultiJson.dump(attributes)
      elsif adapter_class == Lutaml::KeyValue::Adapter::Json::OjAdapter
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

  describe Lutaml::KeyValue::Adapter::Json::StandardAdapter do
    it_behaves_like "a JSON adapter", described_class
  end

  describe Lutaml::KeyValue::Adapter::Json::MultiJsonAdapter do
    it_behaves_like "a JSON adapter", described_class
  end

  describe Lutaml::KeyValue::Adapter::Json::OjAdapter do
    it_behaves_like "a JSON adapter", described_class
  end

  # #767: Serialize#to threads internal options (register, adapter
  # selection) into to_json; json >= 3 raises on unknown keywords, so
  # the adapters must strip them before calling JSON.generate.
  describe "internal option filtering" do
    let(:attributes) { { name: "John Doe", age: 30 } }

    it "does not forward lutaml-internal options to JSON.generate" do
      adapter = Lutaml::KeyValue::Adapter::Json::StandardAdapter.new(attributes)
      json = adapter.to_json(register: nil, adapter: nil,
                             _adapter_override: true)
      expect(json).to eq(JSON.generate(attributes))
    end

    it "keeps JSON generator options and :pretty working" do
      adapter = Lutaml::KeyValue::Adapter::Json::StandardAdapter.new(attributes)
      expect(adapter.to_json(pretty: true))
        .to eq(JSON.pretty_generate(attributes))
      expect(adapter.to_json(ascii_only: true))
        .to eq(JSON.generate(attributes, ascii_only: true))
    end
  end
end
