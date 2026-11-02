# frozen_string_literal: true

require "spec_helper"

# lutaml-model#1089: the KeyValue serializer raised IncorrectModelError
# on values the model layer had accepted — raw scalars and hashes
# stored through the cast chain's pass-through, and Serializable
# siblings accepted at construction via already-serialized pass-through.
# The serializer now coerces accepted values to the declared nested
# type instead of exploding mid-render.
module KvAcceptedValuesSpec
  class Content < Lutaml::Model::Serializable
    attribute :content, :string

    xml do
      map_content to: :content
    end

    key_value do
      map "content", to: :content
    end
  end

  class TypedContent < Content
    attribute :type, :string

    xml do
      map_attribute "type", to: :type
    end

    key_value do
      map "type", to: :type
    end
  end

  class Thing < Lutaml::Model::Serializable
    attribute :label, Content
    attribute :names, TypedContent, collection: true

    key_value do
      map "label", to: :label
      map "names", to: :names
    end
  end
end

RSpec.describe "KeyValue serialization of accepted nested values (#1089)" do
  subject(:thing) { KvAcceptedValuesSpec::Thing.new(label: value, names: names) }

  context "with a raw scalar the constructor stored" do
    let(:value) { "JTA" }
    let(:names) { [] }

    it "wraps onto the declared type's content attribute" do
      expect(thing.to_yaml).to include("content: JTA")
    end

    it "deserializes back to the declared type" do
      parsed = KvAcceptedValuesSpec::Thing.from_yaml(thing.to_yaml)
      expect(parsed.label).to be_a(KvAcceptedValuesSpec::Content)
      expect(parsed.label.content).to eq("JTA")
    end
  end

  context "with a raw hash the constructor stored" do
    let(:value) { { "content" => "Hash form" } }
    let(:names) { [] }

    it "constructs the declared type from the hash" do
      expect(thing.to_yaml).to include("content: Hash form")
    end
  end

  context "with a Serializable sibling of the declared type" do
    let(:value) { KvAcceptedValuesSpec::Content.new(content: "X") }
    let(:names) { [KvAcceptedValuesSpec::Content.new(content: "Sibling")] }

    it "round-trips through the framework hash into the declared type" do
      expect(thing.to_yaml).to include("content: X")
      expect(thing.to_yaml).to include("content: Sibling")
    end

    it "deserializes as the declared type" do
      parsed = KvAcceptedValuesSpec::Thing.from_yaml(thing.to_yaml)
      expect(parsed.names.first).to be_a(KvAcceptedValuesSpec::TypedContent)
      expect(parsed.names.first.content).to eq("Sibling")
    end
  end

  context "with an already-cast value" do
    let(:value) { KvAcceptedValuesSpec::Content.new(content: "fine") }
    let(:names) { [KvAcceptedValuesSpec::TypedContent.new(content: "t")] }

    it "serializes unchanged" do
      expect(thing.to_yaml).to include("content: fine")
      expect(thing.to_yaml).to include("content: t")
    end
  end
end
