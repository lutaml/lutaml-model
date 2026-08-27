# frozen_string_literal: true

require "spec_helper"

module ValuePolicySpec
  # A value type whose whole purpose is to wrap any literal:
  # scalar, list, or map (issue #752).
  class LiteralValue < Lutaml::Model::Type::Value
  end

  class LiteralDoc < Lutaml::Model::Serializable
    attribute :v, LiteralValue
    key_value do
      map "v", to: :v
    end
  end

  class StringsDoc < Lutaml::Model::Serializable
    attribute :v, :string
    key_value do
      map "v", to: :v
    end
  end

  class CollectionDoc < Lutaml::Model::Serializable
    attribute :v, :string, collection: true
    key_value do
      map "v", to: :v
    end
  end
end

RSpec.describe "ValuePolicy shaping of non-collection attributes" do
  describe "user-defined Type::Value subclass" do
    it "receives the whole array from key-value data" do
      expect(ValuePolicySpec::LiteralDoc.from_yaml("v: [a, b]").v)
        .to eq(["a", "b"])
    end

    it "receives an empty array from key-value data" do
      expect(ValuePolicySpec::LiteralDoc.from_yaml("v: []").v).to eq([])
    end

    it "receives the whole hash from key-value data" do
      v = ValuePolicySpec::LiteralDoc.from_yaml("v: {a: 1}").v
      expect(v.value).to eq("a" => 1)
    end

    it "keeps scalar behavior" do
      doc = ValuePolicySpec::LiteralDoc.from_yaml(<<~YAML)
        v: hello
      YAML
      expect(doc.v).to eq("hello")
    end

    it "round-trips an array value through YAML" do
      doc = ValuePolicySpec::LiteralDoc.from_yaml("v: [a, b]")
      expect(ValuePolicySpec::LiteralDoc.from_yaml(doc.to_yaml).v)
        .to eq(["a", "b"])
    end

    it "accepts an array assigned after construction" do
      doc = ValuePolicySpec::LiteralDoc.new(v: "seed")
      doc.v = ["a", "b"]
      expect(doc.v).to eq(["a", "b"])
    end
  end

  describe "built-in scalar types" do
    it "keep the collection: true guidance error" do
      expect { ValuePolicySpec::StringsDoc.from_yaml("v: [a]") }
        .to raise_error(Lutaml::Model::CollectionTrueMissingError)
    end
  end

  describe "collection attributes" do
    it "keep element-wise casting" do
      expect(ValuePolicySpec::CollectionDoc.from_yaml("v: [a, b]").v)
        .to eq(["a", "b"])
    end
  end
end
