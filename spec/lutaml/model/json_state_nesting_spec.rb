# frozen_string_literal: true

require "spec_helper"

# json 3.0 removed JSON::State#[]. Ruby's generator passes a JSON::State to
# #to_json whenever a model is nested inside another JSON.generate call, so the
# model layer must not read option keys off it.
RSpec.describe "a model nested inside JSON.generate" do
  before do
    stub_const("JsonStateNestingModel", Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :age, :integer
    end)
  end

  let(:model) { JsonStateNestingModel.new(name: "John", age: 30) }

  it "serializes inside a Hash" do
    expect(JSON.generate({ "person" => model }))
      .to eq('{"person":{"name":"John","age":30}}')
  end

  it "serializes inside an Array" do
    expect(JSON.generate([model])).to eq('[{"name":"John","age":30}]')
  end

  # The generator's JSON::State carries the surrounding indent context. It has
  # to reach the adapter, not be discarded, or a nested model silently renders
  # compact inside an otherwise pretty document. Reference values are the
  # output of unmodified main on json 2.20.0.
  it "inherits the surrounding indent inside a pretty Hash" do
    expect(JSON.pretty_generate({ "person" => model }))
      .to eq(%({\n  "person": {\n    "name": "John",\n    "age": 30\n  }\n}))
  end

  it "inherits the surrounding indent inside a pretty Array" do
    expect(JSON.pretty_generate([model]))
      .to eq(%([\n  {\n    "name": "John",\n    "age": 30\n  }\n]))
  end

  it "still honours LutaML's own options when called directly" do
    expect(model.to_json(pretty: true))
      .to eq(%({\n  "name": "John",\n  "age": 30\n}))
  end

  # A non-Hash options argument must be replaced, not merely captured -- a
  # falsy one (nil, false) previously stayed in place and the next line called
  # .delete on it.
  it "does not raise on a nil options argument" do
    expect(model.to_json(nil)).to eq('{"name":"John","age":30}')
  end

  it "does not raise on a false options argument" do
    expect(model.to_json(false)).to eq('{"name":"John","age":30}')
  end

  # A non-Hash options argument reaches every format, not just JSON, so the
  # normalisation must not skip format-specific validation on the way past.
  # A type-only model has no root mapping and must refuse to serialise alone.
  it "still applies XML root validation to a non-Hash argument" do
    stub_const("TypeOnlyModel", Class.new(Lutaml::Model::Serializable) do
      attribute :n, :string
    end)

    expect { TypeOnlyModel.new(n: "a").to_xml(nil) }
      .to raise_error(Lutaml::Model::TypeOnlyMappingError)
  end

  it "leaves non-JSON formats untouched" do
    expect(model.to_yaml).to eq("---\nname: John\nage: 30\n")
  end
end
