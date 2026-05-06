# frozen_string_literal: true

require "spec_helper"
require "lutaml/rdf"

RSpec.describe "RDF Namespace edge cases" do
  describe "Namespace immutability" do
    it "prevents URI change after initial set" do
      ns_class = Class.new(Lutaml::Rdf::Namespace)
      ns_class.uri "http://example.org/"
      expect { ns_class.uri "http://other.org/" }.to raise_error(FrozenError)
    end

    it "prevents prefix change after initial set" do
      ns_class = Class.new(Lutaml::Rdf::Namespace)
      ns_class.prefix "ex"
      expect { ns_class.prefix "other" }.to raise_error(FrozenError)
    end
  end

  describe "NamespaceSet collision detection" do
    it "raises when adding two different classes with same prefix" do
      ns1 = Class.new(Lutaml::Rdf::Namespace)
      ns1.uri "http://one.org/"
      ns1.prefix "ex"

      ns2 = Class.new(Lutaml::Rdf::Namespace)
      ns2.uri "http://two.org/"
      ns2.prefix "ex"

      set = Lutaml::Rdf::NamespaceSet.new(ns1)
      expect { set.add(ns2) }.to raise_error(ArgumentError, /conflicts/)
    end

    it "allows adding the same class twice" do
      ns = Class.new(Lutaml::Rdf::Namespace)
      ns.uri "http://example.org/"
      ns.prefix "ex"

      set = Lutaml::Rdf::NamespaceSet.new(ns)
      expect { set.add(ns) }.not_to raise_error
      expect(set.size).to eq(1)
    end
  end

  describe "NamespaceSet edge cases" do
    it "returns nil for unknown prefix lookup" do
      set = Lutaml::Rdf::NamespaceSet.new
      expect(set["unknown"]).to be_nil
    end

    it "returns nil for unknown URI compaction" do
      set = Lutaml::Rdf::NamespaceSet.new
      expect(set.compact("http://unknown.org/thing")).to be_nil
    end

    it "handles empty namespace set" do
      set = Lutaml::Rdf::NamespaceSet.new
      expect(set.size).to eq(0)
      expect(set.empty?).to be(true)
      expect(set.to_a).to eq([])
      expect(set.to_hash).to eq({})
    end

    it "returns value as-is when no colon in compact IRI" do
      set = Lutaml::Rdf::NamespaceSet.new
      expect(set.resolve_compact_iri("plain_name")).to eq("plain_name")
    end
  end

  describe "Iri value object edge cases" do
    it "stores frozen string value" do
      iri = Lutaml::Rdf::Iri.new("http://example.org/")
      expect(iri.value).to be_frozen
    end

    it "compares with Comparable" do
      a = Lutaml::Rdf::Iri.new("http://a.org/")
      b = Lutaml::Rdf::Iri.new("http://b.org/")
      expect(a < b).to be(true)
      expect(b < a).to be(false)
    end

    it "returns nil compact when no namespace matches" do
      iri = Lutaml::Rdf::Iri.new("http://unknown.org/thing")
      set = Lutaml::Rdf::NamespaceSet.new
      expect(iri.compact(set)).to be_nil
    end
  end

  describe "Literal value object edge cases" do
    it "plain literal has no datatype or language" do
      lit = Lutaml::Rdf::Literal.new("hello")
      expect(lit.datatype).to be_nil
      expect(lit.language).to be_nil
    end

    it "handles empty string value" do
      lit = Lutaml::Rdf::Literal.new("")
      expect(lit.to_turtle).to eq('""')
      expect(lit.to_jsonld_term).to eq("")
    end

    it "escapes tabs in Turtle output" do
      lit = Lutaml::Rdf::Literal.new("tab\there")
      expect(lit.to_turtle).to include("\\t")
    end
  end
end
