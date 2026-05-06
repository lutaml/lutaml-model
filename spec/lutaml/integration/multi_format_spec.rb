# frozen_string_literal: true

require "spec_helper"
require "lutaml/turtle"
require "lutaml/jsonld"

RSpec.describe "Multi-format model" do
  before do
    stub_const("TestSkosNs", Class.new(Lutaml::Rdf::Namespace) do
      uri "http://www.w3.org/2004/02/skos/core#"
      prefix "skos"
    end)

    stub_const("MultiFormatModel", Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :description, :string
      attribute :code, :string

      json do
        map "name", to: :name
        map "description", to: :description
        map "code", to: :code
      end

      rdf do
        namespace TestSkosNs

        subject { |m| "http://example.org/concept/#{m.code}" } # rubocop:disable RSpec/NamedSubject

        type "skos:Concept"

        predicate :prefLabel, namespace: TestSkosNs, to: :name
        predicate :definition, namespace: TestSkosNs, to: :description
        predicate :notation, namespace: TestSkosNs, to: :code
      end
    end)
  end

  let(:instance) do
    MultiFormatModel.new(name: "test", description: "desc", code: "42")
  end

  describe "JSON format" do
    it "serializes without @context" do
      json = instance.to_json
      parsed = JSON.parse(json)
      expect(parsed).not_to have_key("@context")
      expect(parsed["name"]).to eq("test")
      expect(parsed["code"]).to eq("42")
    end

    it "round-trips" do
      restored = MultiFormatModel.from_json(instance.to_json)
      expect(restored.name).to eq("test")
      expect(restored.code).to eq("42")
    end
  end

  describe "JSON-LD format" do
    it "serializes with @type and @id" do
      jsonld = instance.to_jsonld
      parsed = JSON.parse(jsonld)
      expect(parsed["@type"]).to eq("skos:Concept")
      expect(parsed["@id"]).to eq("http://example.org/concept/42")
      expect(parsed["prefLabel"]).to eq("test")
    end

    it "round-trips" do
      restored = MultiFormatModel.from_jsonld(instance.to_jsonld)
      expect(restored.name).to eq("test")
      expect(restored.code).to eq("42")
    end
  end

  describe "Turtle format" do
    it "serializes with prefixes and type" do
      turtle = instance.to_turtle
      expect(turtle).to include("@prefix skos:")
      expect(turtle).to include("a skos:Concept")
      expect(turtle).to include("<http://example.org/concept/42>")
      expect(turtle).to include("skos:prefLabel \"test\"")
    end

    it "round-trips" do
      restored = MultiFormatModel.from_turtle(instance.to_turtle)
      expect(restored.name).to eq("test")
      expect(restored.code).to eq("42")
    end
  end

  describe "cross-format independence" do
    it "JSON serialization does not affect JSON-LD" do
      json_parsed = JSON.parse(instance.to_json)
      jsonld_parsed = JSON.parse(instance.to_jsonld)
      expect(json_parsed).not_to have_key("@type")
      expect(jsonld_parsed).to have_key("@type")
    end

    it "JSON-LD serialization does not affect Turtle" do
      instance.to_jsonld
      turtle = instance.to_turtle
      expect(turtle).not_to include("@context")
      expect(turtle).to include("@prefix")
    end
  end
end
