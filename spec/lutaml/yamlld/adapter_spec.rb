# frozen_string_literal: true

require "spec_helper"
require "lutaml/yamlld"

RSpec.describe Lutaml::YamlLd::Adapter do
  let(:yamlld_hash) do
    {
      "@context" => { "name" => "http://example.org/name" },
      "@type" => "Thing",
      "name" => "test",
    }
  end

  describe ".parse" do
    it "parses valid YAML-LD string to hash" do
      yaml = YAML.dump(yamlld_hash)
      result = described_class.parse(yaml)
      expect(result).to eq(yamlld_hash)
    end
  end

  describe "#to_yamlld" do
    it "generates YAML-LD string from hash" do
      adapter = described_class.new(yamlld_hash)
      result = adapter.to_yamlld
      parsed = YAML.safe_load(result)
      expect(parsed["@context"]).to eq({ "name" => "http://example.org/name" })
    end
  end

  it "round-trips parse → generate" do
    yaml = YAML.dump(yamlld_hash)
    parsed = described_class.parse(yaml)
    adapter = described_class.new(parsed)
    result = adapter.to_yamlld
    round_tripped = YAML.safe_load(result)
    expect(round_tripped).to eq(yamlld_hash)
  end

  describe "safe_load enforcement" do
    it "rejects YAML with disallowed class tags" do
      unsafe = "--- !ruby/object:Object {}\n"
      expect do
        described_class.parse(unsafe)
      end.to raise_error(Psych::DisallowedClass)
    end

    it "rejects malformed YAML with Psych::SyntaxError" do
      malformed = "@context: [unterminated"
      expect do
        described_class.parse(malformed)
      end.to raise_error(Psych::SyntaxError)
    end
  end
end
