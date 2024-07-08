# spec/lutaml/model/json_adapter_spec.rb
require "spec_helper"
require "lutaml/model/json_adapter/standard"
require "lutaml/model/json_adapter/multi_json"
require_relative "../../fixtures/sample_model"

RSpec.shared_examples "a JSON adapter" do |adapter_class|
  let(:attributes) { { name: "John Doe", age: 30 } }
  let(:model) { SampleModel.new(attributes) }

  it "serializes to JSON" do
    json = adapter_class.new(attributes).to_json
    expected = if adapter_class == Lutaml::Model::JsonAdapter::StandardDocument
                 JSON.generate(attributes)
               else
                 MultiJson.dump(attributes)
               end
    expect(json).to eq(expected)
  end

  it "deserializes from JSON" do
    json = if adapter_class == Lutaml::Model::JsonAdapter::StandardDocument
             JSON.generate(attributes)
           else
             MultiJson.dump(attributes)
           end

    doc = adapter_class.parse(json)
    new_model = SampleModel.new(doc.to_h)
    expect(new_model.name).to eq("John Doe")
    expect(new_model.age).to eq(30)
  end
end

RSpec.describe Lutaml::Model::JsonAdapter::StandardDocument do
  it_behaves_like "a JSON adapter", described_class
end

RSpec.describe Lutaml::Model::JsonAdapter::MultiJsonDocument do
  it_behaves_like "a JSON adapter", described_class
end
