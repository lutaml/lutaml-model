# frozen_string_literal: true

require "spec_helper"
require "lutaml/jsonld"

RSpec.describe Lutaml::JsonLd::Context do
  subject(:ctx) { described_class.new }

  describe "empty context" do
    it "serializes to empty hash" do
      expect(ctx.to_hash).to eq({})
    end
  end

  describe "#prefix" do
    it "adds namespace prefix from Rdf::Namespace class" do
      ctx.prefix(Lutaml::Rdf::Namespaces::SkosNamespace)
      expect(ctx.to_hash).to include("skos" => "http://www.w3.org/2004/02/skos/core#")
    end

    it "adds multiple prefixes" do
      ctx.prefix(Lutaml::Rdf::Namespaces::SkosNamespace)
      ctx.prefix(Lutaml::Rdf::Namespaces::DctermsNamespace)
      hash = ctx.to_hash
      expect(hash).to include("skos" => "http://www.w3.org/2004/02/skos/core#")
      expect(hash).to include("dcterms" => "http://purl.org/dc/terms/")
    end
  end

  describe "#vocab" do
    it "sets @vocab" do
      ctx.vocab("http://example.org/ns/")
      expect(ctx.to_hash).to include("@vocab" => "http://example.org/ns/")
    end
  end

  describe "#language" do
    it "sets @language" do
      ctx.language("en")
      expect(ctx.to_hash).to include("@language" => "en")
    end
  end

  describe "#base" do
    it "sets @base" do
      ctx.base("http://example.org/")
      expect(ctx.to_hash).to include("@base" => "http://example.org/")
    end
  end

  describe "#term" do
    it "adds simple term as name => id" do
      ctx.term("name", id: "http://example.org/name")
      expect(ctx.to_hash).to include("name" => "http://example.org/name")
    end

    it "adds term with type" do
      ctx.term("date", id: "http://example.org/date", type: "xsd:date")
      expect(ctx.to_hash).to include("date" => {
                                       "@id" => "http://example.org/date", "@type" => "xsd:date"
                                     })
    end

    it "adds term with container" do
      ctx.term("labels", id: "http://example.org/labels", container: :language)
      expect(ctx.to_hash).to include("labels" => {
                                       "@id" => "http://example.org/labels", "@container" => "@language"
                                     })
    end

    it "adds term with reverse" do
      ctx.term("parent", id: "http://example.org/parent", reverse: true)
      expect(ctx.to_hash).to include("parent" => {
                                       "@id" => "http://example.org/parent", "@reverse" => true
                                     })
    end
  end

  describe "#to_hash" do
    it "serializes complete context" do
      ctx.prefix(Lutaml::Rdf::Namespaces::SkosNamespace)
      ctx.vocab("http://example.org/ns/")
      ctx.term("name", id: "http://example.org/name")
      hash = ctx.to_hash
      expect(hash["@vocab"]).to eq("http://example.org/ns/")
      expect(hash["skos"]).to eq("http://www.w3.org/2004/02/skos/core#")
      expect(hash["name"]).to eq("http://example.org/name")
    end
  end

  describe "#resolve" do
    before do
      ctx.prefix(Lutaml::Rdf::Namespaces::SkosNamespace)
      ctx.vocab("http://example.org/ns/")
      ctx.term("status", id: "http://example.org/status")
    end

    it "resolves compact IRI via prefixes" do
      expect(ctx.resolve("skos:prefLabel")).to eq("http://www.w3.org/2004/02/skos/core#prefLabel")
    end

    it "resolves via term definitions" do
      expect(ctx.resolve("status")).to eq("http://example.org/status")
    end

    it "resolves unprefixed name via @vocab" do
      expect(ctx.resolve("unknown")).to eq("http://example.org/ns/unknown")
    end

    it "returns nil for unknown prefix" do
      expect(ctx.resolve("unknown:something")).to be_nil
    end
  end
end
