require "spec_helper"
require_relative "../../../lib/lutaml/model"

module CollectionSingleValueCoercion
  class Item < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      element "item"
      map_element "name", to: :name
    end
  end

  class Basket < Lutaml::Model::Serializable
    attribute :items, Item, collection: true
    attribute :labels, :string, collection: true
    attribute :sizes, :string, collection: 1..2

    xml do
      element "basket"
      map_element "item", to: :items
      map_element "label", to: :labels
      map_element "size", to: :sizes
    end
  end

  class NameParts < Lutaml::Model::Collection
    instances :parts, :string
  end

  class MetadataEntries < Lutaml::Model::Collection
    instances :entries, :hash
  end

  class Person < Lutaml::Model::Serializable
    attribute :name_parts, :string, collection: NameParts
    attribute :metadata_entries, :hash, collection: MetadataEntries

    xml do
      element "person"
      map_element "part", to: :name_parts
    end
  end

  class Coded < Lutaml::Model::Serializable
    attribute :codes, :string, collection: true, pattern: /\A[a-z]+\z/

    xml do
      element "coded"
      map_element "code", to: :codes
    end
  end

  # Pattern applied to an attribute backed by a custom Collection class. The
  # value is a Collection instance (not a plain Array), so pattern validation
  # must flatten it per element rather than treat it as a single non-string.
  class CodedCustom < Lutaml::Model::Serializable
    attribute :codes, :string, collection: NameParts, pattern: /\A[a-z]+\z/

    xml do
      element "coded_custom"
      map_element "code", to: :codes
    end
  end
end

RSpec.describe "single value coercion on collection attributes" do
  describe "setter assignment" do
    it "wraps a single model instance into a one-element array" do
      basket = CollectionSingleValueCoercion::Basket.new
      basket.items = CollectionSingleValueCoercion::Item.new(name: "one")

      expect(basket.items).to be_a(Array)
      expect(basket.items.map(&:name)).to eq(["one"])
    end

    it "wraps a single primitive into a one-element array" do
      basket = CollectionSingleValueCoercion::Basket.new
      basket.labels = "fragile"

      expect(basket.labels).to eq(["fragile"])
    end

    it "leaves nil untouched" do
      basket = CollectionSingleValueCoercion::Basket.new
      basket.labels = nil

      expect(basket.labels).to be_nil
    end

    it "leaves array assignment unchanged" do
      basket = CollectionSingleValueCoercion::Basket.new
      basket.labels = %w[a b]

      expect(basket.labels).to eq(%w[a b])
    end
  end

  describe "constructor assignment" do
    it "wraps a single value passed to the constructor" do
      basket = CollectionSingleValueCoercion::Basket.new(labels: "solo")

      expect(basket.labels).to eq(["solo"])
    end

    it "produces the same shape as parsing one element" do
      parsed = CollectionSingleValueCoercion::Basket.from_xml(
        "<basket><label>solo</label></basket>",
      )
      built = CollectionSingleValueCoercion::Basket.new(labels: "solo")

      expect(built.labels).to eq(parsed.labels)
    end
  end

  describe "bounded collections" do
    it "wraps a single value and satisfies the range validation" do
      basket = CollectionSingleValueCoercion::Basket.new(sizes: "small")

      expect(basket.sizes).to eq(["small"])
      expect { basket.validate! }.not_to raise_error
    end
  end

  describe "custom collection classes" do
    it "wraps a single value into the custom collection" do
      person = CollectionSingleValueCoercion::Person.new
      person.name_parts = "Ada"

      expect(person.name_parts)
        .to be_a(CollectionSingleValueCoercion::NameParts)
      expect(person.name_parts.to_a.size).to eq(1)
    end

    it "routes a plain Array through the collection branch element-wise" do
      person = CollectionSingleValueCoercion::Person.new
      person.name_parts = %w[Ada Lovelace]

      expect(person.name_parts)
        .to be_a(CollectionSingleValueCoercion::NameParts)
      expect(person.name_parts.to_a.size).to eq(2)
    end

    it "does not double-cast arrays for hash-valued custom collections" do
      person = CollectionSingleValueCoercion::Person.new
      person.metadata_entries = [{ "text" => "x" }]

      expect(person.metadata_entries)
        .to be_a(CollectionSingleValueCoercion::MetadataEntries)
      expect(person.metadata_entries.to_a).to eq(["x"])
    end

    it "does not double-cast single values for hash-valued custom collections" do
      person = CollectionSingleValueCoercion::Person.new
      person.metadata_entries = { "text" => "x" }

      expect(person.metadata_entries)
        .to be_a(CollectionSingleValueCoercion::MetadataEntries)
      expect(person.metadata_entries.to_a).to eq(["x"])
    end

    it "rebuilds a fresh collection instead of sharing the assigned one" do
      shared = CollectionSingleValueCoercion::NameParts.new(%w[Ada])
      a = CollectionSingleValueCoercion::Person.new
      b = CollectionSingleValueCoercion::Person.new

      a.name_parts = shared
      b.name_parts = shared

      expect(a.name_parts).not_to be(shared)
      expect(a.name_parts).not_to be(b.name_parts)
      expect(a.name_parts.to_a).to eq(%w[Ada])
    end
  end

  describe "pattern validation on collection attributes" do
    it "validates a coerced single value per element" do
      coded = CollectionSingleValueCoercion::Coded.new(codes: "abc")

      expect(coded.codes).to eq(["abc"])
      expect { coded.validate! }.not_to raise_error
    end

    it "validates each element of an assigned array" do
      coded = CollectionSingleValueCoercion::Coded.new(codes: %w[abc def])

      expect { coded.validate! }.not_to raise_error
    end

    it "rejects an element that violates the pattern" do
      coded = CollectionSingleValueCoercion::Coded.new(codes: %w[abc DEF])

      expect { coded.validate! }
        .to raise_error(Lutaml::Model::ValidationError, /DEF/)
    end

    it "validates each element of a custom Collection per element" do
      coded = CollectionSingleValueCoercion::CodedCustom.new(codes: %w[abc def])

      expect { coded.validate! }.not_to raise_error
    end

    it "rejects a bad element inside a custom Collection" do
      coded = CollectionSingleValueCoercion::CodedCustom.new(codes: %w[abc DEF])

      expect { coded.validate! }
        .to raise_error(Lutaml::Model::ValidationError, /DEF/)
    end
  end

  describe "serialization round-trip" do
    it "serializes a coerced single value as a repeated element would" do
      basket = CollectionSingleValueCoercion::Basket.new
      basket.items = CollectionSingleValueCoercion::Item.new(name: "one")

      round_tripped = CollectionSingleValueCoercion::Basket.from_xml(
        basket.to_xml,
      )
      expect(round_tripped.items.map(&:name)).to eq(["one"])
    end
  end
end
