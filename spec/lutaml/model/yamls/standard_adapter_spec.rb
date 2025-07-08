require "spec_helper"

RSpec.describe Lutaml::Model::Yamls::StandardAdapter do
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

  describe ".parse" do
    context "with valid YAMLS content" do
      it "parses each YAML document as a separate object" do
        results = described_class.parse(valid_yamls_content)
        expect(results).to be_an(Array)
        expect(results.length).to eq(3)
        expect(results.first).to eq({ "name" => "John", "age" => 30 })
        expect(results.last).to eq({ "name" => "Bob", "age" => 35 })
      end
    end

    context "with invalid YAMLS content" do
      it "skips invalid YAML documents and continues parsing" do
        results = described_class.parse(invalid_yamls_content)
        expect(results).to be_an(Array)
        expect(results.length).to eq(2)
        expect(results.first).to eq({ "name" => "John", "age" => 30 })
        expect(results.last).to eq({ "name" => "Bob", "age" => 35 })
      end
    end

    context "with empty documents" do
      let(:yamls_with_empty_docs) do
        <<~YAMLS
          name: John
          ---

          ---
          name: Jane
        YAMLS
      end

      it "skips empty documents" do
        results = described_class.parse(yamls_with_empty_docs)
        expect(results).to be_an(Array)
        expect(results.length).to eq(2)
      end
    end

    context "with single document" do
      let(:single_yaml_doc) do
        <<~YAMLS
          name: John
          age: 30
        YAMLS
      end

      it "parses single document correctly" do
        results = described_class.parse(single_yaml_doc)
        expect(results).to be_an(Array)
        expect(results.length).to eq(1)
        expect(results.first).to eq({ "name" => "John", "age" => 30 })
      end
    end

    context "with complex YAML structures" do
      let(:complex_yamls_content) do
        <<~YAMLS
          name: John
          address:
            street: 123 Main St
            city: New York
          hobbies:
            - reading
            - swimming
          ---
          name: Jane
          address:
            street: 456 Oak Ave
            city: Los Angeles
          hobbies:
            - hiking
            - cooking
        YAMLS
      end

      it "parses complex YAML structures" do
        results = described_class.parse(complex_yamls_content)
        expect(results).to be_an(Array)
        expect(results.length).to eq(2)

        expect(results.first).to eq({
                                      "name" => "John",
                                      "address" => {
                                        "street" => "123 Main St",
                                        "city" => "New York",
                                      },
                                      "hobbies" => ["reading", "swimming"],
                                    })

        expect(results.last).to eq({
                                     "name" => "Jane",
                                     "address" => {
                                       "street" => "456 Oak Ave",
                                       "city" => "Los Angeles",
                                     },
                                     "hobbies" => ["hiking", "cooking"],
                                   })
      end
    end
  end

  describe "#to_yamls" do
    let(:john) { { "name" => "John", "age" => 30 } }
    let(:adapter) { described_class.new([john]) }

    it "generates YAMLS format" do
      expect(adapter.to_yamls.strip).to eq(john.to_yaml.strip)
    end

    context "with multiple objects" do
      let(:jane) { { "name" => "Jane", "age" => 25 } }
      let(:adapter) { described_class.new([john, jane]) }

      let(:expected_yamls) do
        <<~YAMLS.strip
          #{john.to_yaml.strip}
          #{jane.to_yaml.strip}
        YAMLS
      end

      it "generates multiple YAML documents" do
        expect(adapter.to_yamls.strip).to eq(expected_yamls.strip)
      end
    end

    context "with complex data structures" do
      let(:adapter) do
        described_class.new([
                              {
                                "name" => "John",
                                "address" => {
                                  "street" => "123 Main St",
                                  "city" => "New York",
                                },
                                "hobbies" => ["reading", "swimming"],
                              },
                            ])
      end

      it "generates complex YAML structures" do
        result = adapter.to_yamls
        expect(result).to include("name")
        expect(result).to include("address")
        expect(result).to include("hobbies")
      end
    end
  end

  describe "FORMAT_SYMBOL" do
    it "returns :yaml" do
      expect(described_class::FORMAT_SYMBOL).to eq(:yaml)
    end
  end
end
