# frozen_string_literal: true

require "spec_helper"

# Regression spec for issue #987: with a single model member in a union,
# a Hash carrying keys the model does not map must still conform. Unknown
# keys are ignored by every non-union model attribute; strict key
# coverage silently returned nil for the whole attribute instead.
module UnionLenientModelSpec
  class Extensible < Lutaml::Model::Serializable
    attribute :type, :string
    attribute :strict_properties, :boolean

    key_value do
      map "type", to: :type
      map "strictProperties", to: :strict_properties
    end
  end

  class Holder < Lutaml::Model::Serializable
    attribute :value, [Extensible, :boolean]

    key_value do
      map "value", to: :value
    end
  end

  class Other < Lutaml::Model::Serializable
    attribute :celsius, :float

    key_value do
      map "celsius", to: :celsius
    end
  end

  class TwoModelHolder < Lutaml::Model::Serializable
    attribute :value, [Extensible, Other]

    key_value do
      map "value", to: :value
    end
  end

  RSpec.describe "Union with a single model member accepts unmapped keys" do
    it "builds the model when the hash carries unmapped keys" do
      value = Holder.from_json('{"value":{"type":"string","x-ext":1}}').value

      expect(value).to be_a(Extensible)
      expect(value.type).to eq("string")
    end

    it "still accepts hashes with mapped keys only" do
      value = Holder.from_json('{"value":{"type":"string"}}').value

      expect(value).to be_a(Extensible)
      expect(value.type).to eq("string")
    end

    it "keeps boolean members working" do
      expect(Holder.from_json('{"value":true}').value).to be(true)
      expect(Holder.from_json('{"value":false}').value).to be(false)
    end

    it "keeps strict key coverage between several model members" do
      json = '{"value":{"type":"string","celsius":1.0}}'

      expect(TwoModelHolder.from_json(json).value).to be_nil
    end

    it "still requires a match when nothing conforms" do
      expect(Holder.from_json('{"value":3}').value).to be_nil
    end
  end
end
