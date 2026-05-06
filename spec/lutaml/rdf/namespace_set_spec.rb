# frozen_string_literal: true

require "spec_helper"
require "lutaml/rdf"

RSpec.describe Lutaml::Rdf::NamespaceSet do
  subject(:set) do
    described_class.new(
      Lutaml::Rdf::Namespaces::SkosNamespace,
      Lutaml::Rdf::Namespaces::DctermsNamespace,
    )
  end

  describe "construction" do
    it "accepts namespace classes" do
      expect(set.size).to eq(2)
    end

    it "is enumerable" do
      expect(set.map(&:prefix)).to contain_exactly("skos", "dcterms")
    end
  end

  describe "#add" do
    it "adds a namespace" do
      set.add(Lutaml::Rdf::Namespaces::XsdNamespace)
      expect(set.size).to eq(3)
    end

    it "allows adding same class twice" do
      set.add(Lutaml::Rdf::Namespaces::SkosNamespace)
      expect(set.size).to eq(2)
    end

    it "raises on prefix collision with different class" do
      duplicate = Class.new(Lutaml::Rdf::Namespace)
      duplicate.uri "http://other.org/"
      duplicate.prefix "skos"
      expect { set.add(duplicate) }.to raise_error(ArgumentError, /conflicts/)
    end

    it "returns self for chaining" do
      result = set.add(Lutaml::Rdf::Namespaces::XsdNamespace)
      expect(result).to eq(set)
    end
  end

  describe "#[]" do
    it "looks up by prefix" do
      expect(set["skos"]).to eq(Lutaml::Rdf::Namespaces::SkosNamespace)
    end

    it "returns nil for unknown prefix" do
      expect(set["unknown"]).to be_nil
    end
  end

  describe "#resolve_compact_iri" do
    it "resolves known compact IRI" do
      expect(set.resolve_compact_iri("skos:Concept"))
        .to eq("http://www.w3.org/2004/02/skos/core#Concept")
    end

    it "returns value for unknown prefix" do
      expect(set.resolve_compact_iri("foo:Bar")).to eq("foo:Bar")
    end

    it "returns value for no-colon string" do
      expect(set.resolve_compact_iri("Concept")).to eq("Concept")
    end
  end

  describe "#compact" do
    it "compacts full URI to prefixed form" do
      expect(set.compact("http://www.w3.org/2004/02/skos/core#Concept"))
        .to eq("skos:Concept")
    end

    it "returns nil for unknown URI" do
      expect(set.compact("http://unknown.org/Thing")).to be_nil
    end
  end

  describe "#to_hash" do
    it "returns prefix => uri mapping" do
      h = set.to_hash
      expect(h["skos"]).to eq("http://www.w3.org/2004/02/skos/core#")
      expect(h["dcterms"]).to eq("http://purl.org/dc/terms/")
    end
  end

  describe "#merge" do
    it "adds namespaces from another set" do
      other = described_class.new(Lutaml::Rdf::Namespaces::XsdNamespace)
      result = set.merge(other)
      expect(result.size).to eq(3)
      expect(result["xsd"]).to eq(Lutaml::Rdf::Namespaces::XsdNamespace)
    end

    it "returns self" do
      other = described_class.new(Lutaml::Rdf::Namespaces::XsdNamespace)
      expect(set.merge(other)).to equal(set)
    end

    it "skips duplicate prefixes" do
      other = described_class.new(Lutaml::Rdf::Namespaces::SkosNamespace)
      set.merge(other)
      expect(set.size).to eq(2)
    end

    it "returns self when merging with itself" do
      expect(set.merge(set)).to equal(set)
    end
  end
end
