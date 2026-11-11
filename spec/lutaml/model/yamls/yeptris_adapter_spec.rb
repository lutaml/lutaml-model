# frozen_string_literal: true

require "spec_helper"
require "lutaml/yamls/adapter/yeptris_adapter"

RSpec.describe Lutaml::Yamls::Adapter::YeptrisAdapter, if: Lutaml::Yamls::Adapter::YeptrisAdapter.available? do
  let(:valid_yamls_content) do
    <<~YAMLS
      name: John
      age: 30
      ---
      name: Jane
      age: 25
      ---
      name: Bob
      age: 35
    YAMLS
  end

  let(:invalid_yamls_content) do
    <<~YAMLS
      name: John
      age: 30
      ---
      invalid yaml: [
      ---
      name: Bob
      age: 35
    YAMLS
  end

  let(:yamls_with_empty_docs) do
    <<~YAMLS
      name: John
      ---

      ---
      name: Jane
    YAMLS
  end

  describe ".parse" do
    it "parses each YAML document as a separate object" do
      results = described_class.parse(valid_yamls_content)
      expect(results).to be_an(Array)
      expect(results.length).to eq(3)
      expect(results.first).to eq({ "name" => "John", "age" => 30 })
      expect(results.last).to eq({ "name" => "Bob", "age" => 35 })
    end

    it "degrades to the split lane on invalid documents" do
      results = described_class.parse(invalid_yamls_content)
      expect(results).to be_an(Array)
      expect(results.length).to eq(2)
      expect(results.first).to eq({ "name" => "John", "age" => 30 })
      expect(results.last).to eq({ "name" => "Bob", "age" => 35 })
    end

    it "skips empty documents" do
      results = described_class.parse(yamls_with_empty_docs)
      expect(results).to be_an(Array)
      expect(results.length).to eq(2)
    end

    it "parses a single document" do
      results = described_class.parse("name: John\nage: 30\n")
      expect(results).to eq([{ "name" => "John", "age" => 30 }])
    end

    it "raises on a fully-invalid stream instead of returning a blank set" do
      expect { described_class.parse("not: valid: yaml: [") }
        .to raise_error(StandardError)
    end

    it "tolerates mixed streams but raises when nothing valid remains" do
      results = described_class.parse("name: a\n---\nbad: [\n---\nname: c\n")
      expect(results).to eq([{ "name" => "a" }, { "name" => "c" }])
    end
  end
end
