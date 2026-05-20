# frozen_string_literal: true

require "spec_helper"
require "lutaml/rdf"

RSpec.describe Lutaml::Rdf::MappingRule do
  subject(:rule) do
    described_class.new(
      :prefLabel,
      namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
      to: :name,
    )
  end

  describe ".new" do
    it "stores predicate_name as frozen string" do
      expect(rule.predicate_name).to eq("prefLabel")
      expect(rule.predicate_name).to be_frozen
    end

    it "stores to as symbol" do
      expect(rule.to).to eq(:name)
    end

    it "defaults lang_tagged to false" do
      expect(rule.lang_tagged).to be(false)
    end

    it "defaults uri_reference to false" do
      expect(rule.uri_reference).to be(false)
    end

    it "raises when predicate_name is nil" do
      expect do
        described_class.new(nil,
                            namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                            to: :name)
      end.to raise_error(ArgumentError, /predicate_name is required/)
    end

    it "raises when namespace is not a Rdf::Namespace subclass" do
      expect do
        described_class.new(:foo, namespace: String, to: :bar)
      end.to raise_error(ArgumentError, /Rdf::Namespace/)
    end

    it "raises when to is nil" do
      expect do
        described_class.new(:foo,
                            namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                            to: nil)
      end.to raise_error(ArgumentError, /required/)
    end

    it "raises when both lang_tagged and uri_reference are true" do
      expect do
        described_class.new(:foo,
                            namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                            to: :bar,
                            lang_tagged: true,
                            uri_reference: true)
      end.to raise_error(ArgumentError, /mutually exclusive/)
    end
  end

  describe "#kind" do
    it "returns :plain by default" do
      expect(rule.kind).to eq(:plain)
    end

    it "returns :lang_tagged when lang_tagged" do
      r = described_class.new(:prefLabel,
                              namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                              to: :name, lang_tagged: true)
      expect(r.kind).to eq(:lang_tagged)
    end

    it "returns :uri_reference when uri_reference" do
      r = described_class.new(:related,
                              namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                              to: :related, uri_reference: true)
      expect(r.kind).to eq(:uri_reference)
    end
  end

  describe "#uri" do
    it "resolves predicate name to full URI via namespace" do
      expect(rule.uri).to eq("http://www.w3.org/2004/02/skos/core#prefLabel")
    end
  end

  describe "#prefixed_name" do
    it "returns prefix:local form" do
      expect(rule.prefixed_name).to eq("skos:prefLabel")
    end
  end
end
