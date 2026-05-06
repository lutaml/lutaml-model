# frozen_string_literal: true

require "spec_helper"
require "lutaml/rdf"

RSpec.describe Lutaml::Rdf::Mapping do
  subject(:mapping) { described_class.new }

  describe "#namespace" do
    it "builds a NamespaceSet from namespace classes" do
      mapping.namespace(
        Lutaml::Rdf::Namespaces::SkosNamespace,
        Lutaml::Rdf::Namespaces::DctermsNamespace,
      )
      expect(mapping.namespace_set.size).to eq(2)
      expect(mapping.namespace_set["skos"]).to eq(Lutaml::Rdf::Namespaces::SkosNamespace)
    end
  end

  describe "#subject" do
    it "stores subject generator proc" do
      mapping.subject { |obj| "http://example.org/#{obj.name}" }
      expect(mapping.rdf_subject).to be_a(Proc)
    end

    it "returns nil when no subject block given" do
      expect(mapping.rdf_subject).to be_nil
    end
  end

  describe "#type" do
    it "stores RDF type" do
      mapping.type("skos:Concept")
      expect(mapping.rdf_type).to eq("skos:Concept")
    end
  end

  describe "#predicate" do
    it "creates MappingRule with namespace reference" do
      mapping.predicate(
        :prefLabel,
        namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
        to: :name,
      )
      expect(mapping.rdf_predicates.length).to eq(1)
      rule = mapping.rdf_predicates.first
      expect(rule).to be_a(Lutaml::Rdf::MappingRule)
      expect(rule.predicate_name).to eq("prefLabel")
      expect(rule.to).to eq(:name)
      expect(rule.lang_tagged).to be(false)
    end

    it "creates MappingRule with lang_tagged option" do
      mapping.predicate(
        :prefLabel,
        namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
        to: :name,
        lang_tagged: true,
      )
      expect(mapping.rdf_predicates.first.lang_tagged).to be(true)
    end

    it "registers multiple predicates" do
      mapping.predicate(:prefLabel,
                        namespace: Lutaml::Rdf::Namespaces::SkosNamespace, to: :name)
      mapping.predicate(:source,
                        namespace: Lutaml::Rdf::Namespaces::DctermsNamespace, to: :source)
      expect(mapping.rdf_predicates.length).to eq(2)
    end

    it "resolves predicate URI" do
      mapping.predicate(:prefLabel,
                        namespace: Lutaml::Rdf::Namespaces::SkosNamespace, to: :name)
      expect(mapping.rdf_predicates.first.uri).to eq("http://www.w3.org/2004/02/skos/core#prefLabel")
    end

    it "produces prefixed name" do
      mapping.predicate(:prefLabel,
                        namespace: Lutaml::Rdf::Namespaces::SkosNamespace, to: :name)
      expect(mapping.rdf_predicates.first.prefixed_name).to eq("skos:prefLabel")
    end

    it "validates namespace is a Rdf::Namespace subclass" do
      expect do
        mapping.predicate(:foo, namespace: String, to: :bar)
      end.to raise_error(ArgumentError, /Rdf::Namespace/)
    end

    it "validates :to is required" do
      expect do
        mapping.predicate(:foo,
                          namespace: Lutaml::Rdf::Namespaces::SkosNamespace, to: nil)
      end.to raise_error(ArgumentError, /required/)
    end
  end

  describe "#members" do
    it "creates MemberRule" do
      mapping.members(:items)
      expect(mapping.rdf_members.length).to eq(1)
      expect(mapping.rdf_members.first.attr_name).to eq(:items)
    end
  end

  describe "#mappings" do
    it "returns the predicate list" do
      mapping.predicate(:prefLabel,
                        namespace: Lutaml::Rdf::Namespaces::SkosNamespace, to: :name)
      mapping.predicate(:definition,
                        namespace: Lutaml::Rdf::Namespaces::SkosNamespace, to: :desc)
      expect(mapping.mappings).to eq(mapping.rdf_predicates)
    end
  end

  describe "#finalize" do
    it "is a no-op that accepts a mapper class" do
      expect { mapping.finalize(String) }.not_to raise_error
    end
  end

  describe "#finalized?" do
    it "returns true" do
      expect(mapping.finalized?).to be(true)
    end
  end

  describe "#map_element" do
    it "raises IncorrectMappingArgumentsError" do
      expect do
        mapping.map_element("name", to: :name)
      end.to raise_error(Lutaml::Model::IncorrectMappingArgumentsError,
                         /predicate/)
    end
  end

  describe "#deep_dup" do
    before do
      mapping.namespace(
        Lutaml::Rdf::Namespaces::SkosNamespace,
        Lutaml::Rdf::Namespaces::DctermsNamespace,
      )
      mapping.subject { |m| "http://example.org/#{m.name}" }
      mapping.type("skos:Concept")
      mapping.predicate(:prefLabel,
                        namespace: Lutaml::Rdf::Namespaces::SkosNamespace, to: :name)
    end

    it "copies all fields" do
      duped = mapping.deep_dup
      expect(duped.namespace_set.size).to eq(2)
      expect(duped.rdf_subject).to be_a(Proc)
      expect(duped.rdf_type).to eq("skos:Concept")
      expect(duped.rdf_predicates.length).to eq(1)
    end

    it "does not share predicate state with original" do
      duped = mapping.deep_dup
      duped.predicate(:source,
                      namespace: Lutaml::Rdf::Namespaces::DctermsNamespace, to: :source)
      expect(mapping.rdf_predicates.length).to eq(1)
      expect(duped.rdf_predicates.length).to eq(2)
    end
  end
end
