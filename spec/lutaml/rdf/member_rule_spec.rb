# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/lutaml/rdf"

RSpec.describe Lutaml::Rdf::MemberRule do
  describe ".new" do
    it "stores attr_name as symbol" do
      rule = described_class.new(:concepts)
      expect(rule.attr_name).to eq(:concepts)
    end

    it "converts string attr_name to symbol" do
      rule = described_class.new("concepts")
      expect(rule.attr_name).to eq(:concepts)
    end

    it "raises ArgumentError when predicate_name given without namespace" do
      expect do
        described_class.new(:items, predicate_name: :member)
      end.to raise_error(ArgumentError, /namespace is required/)
    end

    it "allows both predicate_name and namespace together" do
      rule = described_class.new(:items,
                                 predicate_name: :member,
                                 namespace: Lutaml::Rdf::Namespaces::SkosNamespace)
      expect(rule.predicate_name).to eq(:member)
    end

    it "raises ArgumentError when predicate_name and link both given" do
      expect do
        described_class.new(:items,
                            predicate_name: :member,
                            namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                            link: "skos:member")
      end.to raise_error(ArgumentError, /mutually exclusive/)
    end
  end

  describe "#linked?" do
    it "returns false when no linking option" do
      rule = described_class.new(:items)
      expect(rule.linked?).to be(false)
    end

    it "returns true when predicate_name is set" do
      rule = described_class.new(:items,
                                 predicate_name: :member,
                                 namespace: Lutaml::Rdf::Namespaces::SkosNamespace)
      expect(rule.linked?).to be(true)
    end

    it "returns true when link is a String" do
      rule = described_class.new(:items, link: "skos:member")
      expect(rule.linked?).to be(true)
    end

    it "returns true when link is a Proc" do
      rule = described_class.new(:items, link: ->(m) { "skos:#{m}" })
      expect(rule.linked?).to be(true)
    end
  end

  describe "#linked_predicate_uri" do
    it "returns nil when no linking predicate" do
      rule = described_class.new(:items)
      expect(rule.linked_predicate_uri).to be_nil
    end

    it "resolves the linking predicate URI" do
      rule = described_class.new(:items,
                                 predicate_name: :member,
                                 namespace: Lutaml::Rdf::Namespaces::SkosNamespace)
      expect(rule.linked_predicate_uri).to eq("http://www.w3.org/2004/02/skos/core#member")
    end

    it "returns nil when link is a String (not static)" do
      rule = described_class.new(:items, link: "skos:member")
      expect(rule.linked_predicate_uri).to be_nil
    end
  end

  describe "#link_predicate_for" do
    let(:mapping) do
      instance = Lutaml::Rdf::Mapping.new
      instance.namespace(
        Lutaml::Rdf::Namespaces::SkosNamespace,
        Lutaml::Rdf::Namespaces::DctermsNamespace,
      )
      instance
    end

    let(:resolver) { mapping.namespace_set.method(:resolve_compact_iri) }

    it "resolves String link via resolver" do
      rule = described_class.new(:items, link: "skos:member")
      expect(rule.link_predicate_for(nil, resolver))
        .to eq("http://www.w3.org/2004/02/skos/core#member")
    end

    it "resolves Proc link by calling with member" do
      rule = described_class.new(:items,
                                 link: ->(m) { "skos:#{m.type}" })
      member = Struct.new(:type).new("Concept")
      expect(rule.link_predicate_for(member, resolver))
        .to eq("http://www.w3.org/2004/02/skos/core#Concept")
    end

    it "returns URI as-is from Proc when prefix not found" do
      rule = described_class.new(:items,
                                 link: ->(m) { "http://example.org/#{m.id}" })
      member = Struct.new(:id).new("42")
      expect(rule.link_predicate_for(member, resolver))
        .to eq("http://example.org/42")
    end

    it "returns nil when no link" do
      rule = described_class.new(:items)
      expect(rule.link_predicate_for(nil, resolver)).to be_nil
    end
  end

  describe "#resolve_link_uri" do
    let(:mapping) do
      instance = Lutaml::Rdf::Mapping.new
      instance.namespace(Lutaml::Rdf::Namespaces::SkosNamespace)
      instance
    end

    let(:resolver) { mapping.namespace_set.method(:resolve_compact_iri) }

    it "uses linked_predicate_uri for static links" do
      rule = described_class.new(:items,
                                 predicate_name: :member,
                                 namespace: Lutaml::Rdf::Namespaces::SkosNamespace)
      expect(rule.resolve_link_uri(nil, resolver))
        .to eq("http://www.w3.org/2004/02/skos/core#member")
    end

    it "uses link_predicate_for for String links" do
      rule = described_class.new(:items, link: "skos:member")
      expect(rule.resolve_link_uri(nil, resolver))
        .to eq("http://www.w3.org/2004/02/skos/core#member")
    end

    it "uses link_predicate_for for Proc links" do
      rule = described_class.new(:items,
                                 link: ->(m) { "skos:#{m.type}" })
      member = Struct.new(:type).new("Concept")
      expect(rule.resolve_link_uri(member, resolver))
        .to eq("http://www.w3.org/2004/02/skos/core#Concept")
    end

    it "returns nil when not linked" do
      rule = described_class.new(:items)
      expect(rule.resolve_link_uri(nil, resolver)).to be_nil
    end
  end
end
