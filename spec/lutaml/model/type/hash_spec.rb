require "spec_helper"

RSpec.describe Lutaml::Model::Type::Hash do
  describe ".cast" do
    it "returns nil for nil input" do
      expect(described_class.cast(nil)).to be_nil
    end

    it "returns text content from a MappingHash with only text key" do
      hash = Lutaml::Model::MappingHash.new
      hash["text"] = "content"
      expect(described_class.cast(hash)).to eq "content"
    end

    # lutaml/lutaml-model#1013: a "text" key holding structured data
    # (or appearing alongside other keys in non-XML data) is ordinary
    # data and must round-trip verbatim
    it "preserves a structured text key from a plain hash" do
      hash = { "text" => { "type" => "string", "description" => "y" } }
      expect(described_class.cast(hash)).to eq hash
    end

    it "preserves text alongside other keys in a plain hash" do
      hash = { "text" => "content", "other" => "value" }
      expect(described_class.cast(hash)).to eq hash
    end

    it "preserves an elements key from a plain hash" do
      hash = { "elements" => [{ "a" => 1 }] }
      expect(described_class.cast(hash)).to eq hash
    end

    it "normalizes MappingHash to regular Hash" do
      mapping_hash = Lutaml::Model::MappingHash.new
      mapping_hash["key"] = "value"
      expect(described_class.cast(mapping_hash)).to eq({ "key" => "value" })
    end

    context "with nested hashes" do
      it "filters out text keys from nested MappingHashes" do
        child1 = Lutaml::Model::MappingHash.new
        child1["text"] = "content1"
        child1["other"] = "value1"
        child2 = Lutaml::Model::MappingHash.new
        child2["text"] = "content2"
        child2["other"] = "value2"
        input = Lutaml::Model::MappingHash.new
        input["key1"] = child1
        input["key2"] = child2
        expected = {
          "key1" => { "other" => "value1" },
          "key2" => { "other" => "value2" },
        }
        expect(described_class.cast(input)).to eq(expected)
      end

      it "preserves text keys in nested plain hashes" do
        input = {
          "key1" => { "text" => "content1", "other" => "value1" },
          "key2" => { "text" => "content2", "other" => "value2" },
        }
        expect(described_class.cast(input)).to eq(input)
      end
    end

    context "with non-hash values" do
      let(:input) do
        {
          "string" => "value",
          "number" => 42,
          "array" => [1, 2, 3],
        }
      end

      it "preserves non-hash values" do
        expect(described_class.cast(input)).to eq input
      end
    end
  end

  describe ".serialize" do
    it "returns nil for nil input" do
      expect(described_class.serialize(nil)).to be_nil
    end

    it "converts hash to hash" do
      hash = { "key" => "value" }
      expect(described_class.serialize(hash)).to eq hash
    end

    it "converts arbitrary object responding to to_h" do
      obj = instance_double(Hash, to_h: { "key" => "value" })
      expect(described_class.serialize(obj)).to eq({ "key" => "value" })
    end
  end
end
