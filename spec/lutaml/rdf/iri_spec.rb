# frozen_string_literal: true

require "spec_helper"
require "lutaml/rdf"

RSpec.describe Lutaml::Rdf::Iri do
  subject(:iri) { described_class.new("http://example.org/ns/Concept") }

  it "stores frozen value" do
    expect(iri.value).to eq("http://example.org/ns/Concept")
    expect(iri.value).to be_frozen
  end

  it "coerces to string" do
    expect(iri.to_s).to eq("http://example.org/ns/Concept")
  end

  describe "equality" do
    it "equals Iri with same value" do
      other = described_class.new("http://example.org/ns/Concept")
      expect(iri).to eq(other)
    end

    it "does not equal Iri with different value" do
      other = described_class.new("http://other.org/Thing")
      expect(iri).not_to eq(other)
    end

    it "has consistent hash" do
      other = described_class.new("http://example.org/ns/Concept")
      expect(iri.hash).to eq(other.hash)
    end
  end

  describe "comparable" do
    it "compares by value" do
      a = described_class.new("http://a.org/")
      b = described_class.new("http://b.org/")
      expect(a < b).to be true
    end
  end

  describe "#expand" do
    let(:ns_set) do
      Lutaml::Rdf::NamespaceSet.new(
        Lutaml::Rdf::Namespaces::SkosNamespace,
      )
    end

    it "expands compact IRI via namespace set" do
      iri = described_class.new("skos:Concept")
      expect(iri.expand(ns_set)).to eq("http://www.w3.org/2004/02/skos/core#Concept")
    end
  end

  describe "#compact" do
    let(:ns_set) do
      Lutaml::Rdf::NamespaceSet.new(
        Lutaml::Rdf::Namespaces::SkosNamespace,
      )
    end

    it "compacts full URI to prefixed form" do
      iri = described_class.new("http://www.w3.org/2004/02/skos/core#Concept")
      expect(iri.compact(ns_set)).to eq("skos:Concept")
    end

    it "returns nil for unknown URI" do
      iri = described_class.new("http://unknown.org/Thing")
      expect(iri.compact(ns_set)).to be_nil
    end
  end
end
