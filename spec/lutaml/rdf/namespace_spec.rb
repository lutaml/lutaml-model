# frozen_string_literal: true

require "spec_helper"
require "lutaml/rdf"

RSpec.describe Lutaml::Rdf::Namespace do
  describe "base class" do
    it "stores uri at class level" do
      ns = Class.new(described_class)
      ns.uri "http://example.org/ns/"
      expect(ns.uri).to eq("http://example.org/ns/")
    end

    it "stores prefix at class level" do
      ns = Class.new(described_class)
      ns.prefix "ex"
      expect(ns.prefix).to eq("ex")
    end

    it "casts prefix to string" do
      ns = Class.new(described_class)
      ns.prefix :ex
      expect(ns.prefix).to eq("ex")
    end

    it "freezes uri" do
      ns = Class.new(described_class)
      ns.uri "http://example.org/ns/"
      expect(ns.uri).to be_frozen
    end

    it "freezes prefix" do
      ns = Class.new(described_class)
      ns.prefix "ex"
      expect(ns.prefix).to be_frozen
    end

    it "raises FrozenError when uri set twice" do
      ns = Class.new(described_class)
      ns.uri "http://first.org/"
      expect { ns.uri "http://second.org/" }.to raise_error(FrozenError)
    end

    it "raises FrozenError when prefix set twice" do
      ns = Class.new(described_class)
      ns.prefix "a"
      expect { ns.prefix "b" }.to raise_error(FrozenError)
    end

    describe "#[]" do
      it "resolves local name to full URI" do
        ns = Class.new(described_class)
        ns.uri "http://example.org/ns/"
        expect(ns["someName"]).to eq("http://example.org/ns/someName")
      end
    end

    describe ".prefixed" do
      it "resolves local name to compact form" do
        ns = Class.new(described_class)
        ns.prefix "ex"
        expect(ns.prefixed("someName")).to eq("ex:someName")
      end
    end

    it "each subclass has independent state" do
      ns1 = Class.new(described_class)
      ns1.uri "http://ns1.org/"
      ns1.prefix "ns1"

      ns2 = Class.new(described_class)
      ns2.uri "http://ns2.org/"
      ns2.prefix "ns2"

      expect(ns1.uri).to eq("http://ns1.org/")
      expect(ns2.uri).to eq("http://ns2.org/")
      expect(ns1.prefix).to eq("ns1")
      expect(ns2.prefix).to eq("ns2")
    end

    describe "equality" do
      it "equals another namespace class with same uri and prefix" do
        a = Class.new(described_class)
        a.uri "http://example.org/"
        a.prefix "ex"

        b = Class.new(described_class)
        b.uri "http://example.org/"
        b.prefix "ex"

        expect(a).to eq(b)
      end

      it "does not equal with different uri" do
        a = Class.new(described_class)
        a.uri "http://a.org/"
        a.prefix "ex"

        b = Class.new(described_class)
        b.uri "http://b.org/"
        b.prefix "ex"

        expect(a).not_to eq(b)
      end
    end

    describe "#to_s" do
      it "includes class name, prefix, and uri" do
        ns = Class.new(described_class)
        ns.uri "http://example.org/"
        ns.prefix "ex"
        expect(ns.to_s).to include("prefix: \"ex\"")
        expect(ns.to_s).to include("uri: \"http://example.org/\"")
      end
    end
  end

  describe ".resolve_compact_iri" do
    let(:namespaces) do
      [
        Lutaml::Rdf::Namespaces::SkosNamespace,
        Lutaml::Rdf::Namespaces::DctermsNamespace,
      ]
    end

    it "resolves known prefix to full URI" do
      expect(described_class.resolve_compact_iri("skos:Concept", namespaces))
        .to eq("http://www.w3.org/2004/02/skos/core#Concept")
    end

    it "returns value as-is when prefix is unknown" do
      expect(described_class.resolve_compact_iri("unknown:Thing", namespaces))
        .to eq("unknown:Thing")
    end

    it "returns value as-is when no colon present" do
      expect(described_class.resolve_compact_iri("Concept", namespaces))
        .to eq("Concept")
    end
  end

  describe "W3C namespace classes" do
    describe Lutaml::Rdf::Namespaces::SkosNamespace do
      subject(:ns) { described_class }

      it "has SKOS URI" do
        expect(ns.uri).to eq("http://www.w3.org/2004/02/skos/core#")
      end

      it "has skos prefix" do
        expect(ns.prefix).to eq("skos")
      end

      it "resolves prefLabel to full URI" do
        expect(ns["prefLabel"]).to eq("http://www.w3.org/2004/02/skos/core#prefLabel")
      end

      it "resolves Concept to compact form" do
        expect(ns.prefixed("Concept")).to eq("skos:Concept")
      end
    end

    describe Lutaml::Rdf::Namespaces::DctermsNamespace do
      subject(:ns) { described_class }

      it "has DCTERMS URI" do
        expect(ns.uri).to eq("http://purl.org/dc/terms/")
      end

      it "has dcterms prefix" do
        expect(ns.prefix).to eq("dcterms")
      end

      it "resolves source to compact form" do
        expect(ns.prefixed("source")).to eq("dcterms:source")
      end
    end

    describe Lutaml::Rdf::Namespaces::RdfNamespace do
      subject(:ns) { described_class }

      it "has RDF URI" do
        expect(ns.uri).to eq("http://www.w3.org/1999/02/22-rdf-syntax-ns#")
      end

      it "has rdf prefix" do
        expect(ns.prefix).to eq("rdf")
      end

      it "resolves type to compact form" do
        expect(ns.prefixed("type")).to eq("rdf:type")
      end
    end

    describe Lutaml::Rdf::Namespaces::RdfSyntaxNamespace do
      it "is the same class as RdfNamespace alias" do
        expect(described_class).to eq(Lutaml::Rdf::Namespaces::RdfNamespace)
      end
    end

    describe Lutaml::Rdf::Namespaces::RdfsNamespace do
      subject(:ns) { described_class }

      it "has RDFS URI" do
        expect(ns.uri).to eq("http://www.w3.org/2000/01/rdf-schema#")
      end

      it "has rdfs prefix" do
        expect(ns.prefix).to eq("rdfs")
      end
    end

    describe Lutaml::Rdf::Namespaces::OwlNamespace do
      subject(:ns) { described_class }

      it "has OWL URI" do
        expect(ns.uri).to eq("http://www.w3.org/2002/07/owl#")
      end

      it "has owl prefix" do
        expect(ns.prefix).to eq("owl")
      end
    end

    describe Lutaml::Rdf::Namespaces::XsdNamespace do
      subject(:ns) { described_class }

      it "has XSD URI" do
        expect(ns.uri).to eq("http://www.w3.org/2001/XMLSchema#")
      end

      it "has xsd prefix" do
        expect(ns.prefix).to eq("xsd")
      end

      it "resolves date to compact form" do
        expect(ns.prefixed("date")).to eq("xsd:date")
      end
    end
  end
end
