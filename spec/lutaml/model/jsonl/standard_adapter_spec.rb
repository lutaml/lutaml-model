require "spec_helper"

RSpec.describe Lutaml::Model::Jsonl::StandardAdapter do
  let(:valid_jsonl_content) do
    <<~JSONL
      {"name": "John", "age": 30}
      {"name": "Jane", "age": 25}
      {"name": "Bob", "age": 35}
    JSONL
  end

  let(:invalid_jsonl_content) do
    <<~JSONL
      {"name": "John", "age": 30}
      invalid json
      {"name": "Bob", "age": 35}
    JSONL
  end

  describe ".parse" do
    context "with valid JSONL content" do
      it "parses each line as a JSON object" do
        results = described_class.parse(valid_jsonl_content)
        expect(results).to be_an(Array)
        expect(results.length).to eq(3)
        expect(results.first).to eq({ "name" => "John", "age" => 30 })
        expect(results.last).to eq({ "name" => "Bob", "age" => 35 })
      end
    end

    context "with invalid JSONL content" do
      it "skips invalid lines and continues parsing" do
        results = described_class.parse(invalid_jsonl_content)
        expect(results).to be_an(Array)
        expect(results.length).to eq(2)
        expect(results.first).to eq({ "name" => "John", "age" => 30 })
        expect(results.last).to eq({ "name" => "Bob", "age" => 35 })
      end
    end

    context "with empty lines" do
      let(:jsonl_with_empty_lines) do
        <<~JSONL
          {"name": "John"}

          {"name": "Jane"}
        JSONL
      end

      it "skips empty lines" do
        results = described_class.parse(jsonl_with_empty_lines)
        expect(results).to be_an(Array)
        expect(results.length).to eq(2)
      end
    end
  end

  describe "#to_jsonl" do
    let(:adapter) { described_class.new([{ "name" => "John", "age" => 30 }]) }

    it "generates JSONL format" do
      expect(adapter.to_jsonl).to eq('{"name":"John","age":30}')
    end

    context "with multiple objects" do
      let(:adapter) do
        described_class.new([
                              { "name" => "John", "age" => 30 },
                              { "name" => "Jane", "age" => 25 },
                            ])
      end

      let(:expected_jsonl) do
        <<~JSONL.strip
          {"name":"John","age":30}
          {"name":"Jane","age":25}
        JSONL
      end

      it "generates multiple lines" do
        expect(adapter.to_jsonl).to eq(expected_jsonl)
      end
    end
  end

  describe "FORMAT_SYMBOL" do
    it "returns :jsonl" do
      expect(described_class::FORMAT_SYMBOL).to eq(:jsonl)
    end
  end
end
