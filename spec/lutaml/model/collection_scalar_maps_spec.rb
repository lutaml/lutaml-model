# frozen_string_literal: true

require "spec_helper"

# lutaml-model#1086: on a Collection subclass, scalar `map` declarations
# in key_value were silently ignored alongside `instances` — the scalar
# attributes neither serialized nor deserialized (data loss, no error).
# The document is hash-shaped (instance key plus scalar keys) when
# scalar mappings are declared; collections without scalar mappings keep
# the legacy bare items array.
module CollectionScalarMapsSpec
  class Entry < Lutaml::Model::Serializable
    attribute :name, :string
    key_value { map "name", to: :name }
  end

  class StampToy < Lutaml::Model::Collection
    instances :entries, Entry
    attribute :stamp, :integer, default: -> { 0 }
    key_value do
      map "entries", to: :entries
      map "stamp", to: :stamp
    end
  end
end

RSpec.describe "Collection with scalar key_value mappings (#1086)" do
  let(:toy) do
    collection = CollectionScalarMapsSpec::StampToy.new
    collection.entries = [CollectionScalarMapsSpec::Entry.new(name: "x")]
    collection.stamp = 42
    collection
  end

  it "serializes the scalars alongside the instances" do
    expect(toy.to_yaml).to include("stamp: 42")
    expect(toy.to_yaml).to include("entries:")
  end

  it "deserializes the scalars from the hash-shaped document" do
    parsed = CollectionScalarMapsSpec::StampToy.from_yaml(toy.to_yaml)
    expect(parsed.stamp).to eq(42)
    expect(parsed.entries.size).to eq(1)
    expect(parsed.entries.first.name).to eq("x")
  end

  it "keeps the legacy bare-array document parseable" do
    parsed = CollectionScalarMapsSpec::StampToy.from_yaml("---\n- name: y\n")
    expect(parsed).to be_a(CollectionScalarMapsSpec::StampToy)
    expect(parsed.entries.size).to eq(1)
    expect(parsed.entries.first.name).to eq("y")
  end

  it "round-trips through the hash shape" do
    parsed = CollectionScalarMapsSpec::StampToy.from_yaml(toy.to_yaml)
    expect(parsed.to_yaml).to eq(toy.to_yaml)
  end
end
