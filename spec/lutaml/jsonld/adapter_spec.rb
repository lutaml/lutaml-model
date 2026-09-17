# frozen_string_literal: true

require "spec_helper"
require "lutaml/jsonld"

RSpec.describe Lutaml::JsonLd::Adapter do
  let(:jsonld_hash) do
    {
      "@context" => { "name" => "http://example.org/name" },
      "@type" => "Thing",
      "name" => "test",
    }
  end

  describe ".parse" do
    it "parses valid JSON-LD string to hash" do
      json = JSON.generate(jsonld_hash)
      result = described_class.parse(json)
      expect(result).to eq(jsonld_hash.transform_keys(&:to_s))
    end
  end

  describe "#to_jsonld" do
    it "generates JSON-LD string from hash" do
      adapter = described_class.new(jsonld_hash)
      result = adapter.to_jsonld
      parsed = JSON.parse(result)
      expect(parsed["@context"]).to eq({ "name" => "http://example.org/name" })
    end

    it "supports pretty generation" do
      adapter = described_class.new(jsonld_hash)
      result = adapter.to_jsonld(pretty: true)
      expect(result).to include("\n")
    end
  end

  it "round-trips parse → generate" do
    json = JSON.generate(jsonld_hash)
    parsed = described_class.parse(json)
    adapter = described_class.new(parsed)
    result = adapter.to_jsonld
    round_tripped = JSON.parse(result)
    expect(round_tripped).to eq(jsonld_hash.transform_keys(&:to_s))
  end

  describe "a JSON::State handed to #to_jsonld" do
    subject(:document) { described_class.new({ "@id" => "urn:x", "n" => 1 }) }

    # Ruby's generator only ever calls #to_json, so a state reaches #to_jsonld
    # only from a direct caller. json 3.0 removed JSON::State#[], so the state
    # must be forwarded to the payload rather than read as an options hash.
    it "honours a state that carries formatting" do
      state = JSON::State.new(indent: "  ", object_nl: "\n", space: " ")

      expect(document.to_jsonld(state))
        .to eq(%({\n  "@id": "urn:x",\n  "n": 1\n}))
    end

    it "renders compactly for a default state" do
      expect(document.to_jsonld(JSON::State.new))
        .to eq('{"@id":"urn:x","n":1}')
    end
  end
end
