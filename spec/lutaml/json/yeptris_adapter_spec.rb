# frozen_string_literal: true

require "spec_helper"
begin
  require "lutaml/json/adapter/yeptris_adapter"
rescue LoadError
  # yeptris ships no platform gem here (e.g. Windows): every example skips.
end

YEPTRIS_AVAILABLE = defined?(Yeptris)

RSpec.describe(YEPTRIS_AVAILABLE ? Lutaml::Json::Adapter::YeptrisAdapter : Object) do
  before { skip "yeptris is not available on this platform" unless YEPTRIS_AVAILABLE }

  let(:attributes) { { "name" => "John", "age" => 30, "roles" => %w[admin dev] } }

  describe ".parse" do
    it "parses a JSON document into a hash" do
      expect(described_class.parse('{"name":"John","age":30,"roles":["admin","dev"]}'))
        .to eq(attributes)
    end

    it "parses scalars and nulls like JSON.parse" do
      expect(described_class.parse('{"a":1.5,"b":null,"c":true,"d":"1e3"}'))
        .to eq("a" => 1.5, "b" => nil, "c" => true, "d" => "1e3")
    end

    it "raises on invalid JSON" do
      expect { described_class.parse("{nope") }
        .to raise_error(Yeptris::JSON::ParseError)
    end
  end

  describe "#to_json" do
    subject(:document) { described_class.new(attributes) }

    it "serializes via the inherited json generator" do
      expect(document.to_json)
        .to eq('{"name":"John","age":30,"roles":["admin","dev"]}')
    end
  end

  describe "round trip through a model" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :roles, :string, collection: true

        key_value do
          map "name", to: :name
          map "roles", to: :roles
        end
      end
    end

    it "deserializes via the yeptris engine and serializes back" do
      model = model_class.from_json('{"name":"John","roles":["admin","dev"]}')
      expect(model.name).to eq("John")
      expect(model.roles).to eq(%w[admin dev])
      expect(model_class.from_json(model.to_json).roles).to eq(%w[admin dev])
    end
  end
end
