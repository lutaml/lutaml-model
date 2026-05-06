# frozen_string_literal: true

require "spec_helper"
require "lutaml/jsonld"

RSpec.describe Lutaml::JsonLd::Transform do
  before do
    stub_const("TestSkosNs", Class.new(Lutaml::Rdf::Namespace) do
      uri "http://www.w3.org/2004/02/skos/core#"
      prefix "skos"
    end)

    stub_const("TestExNs", Class.new(Lutaml::Rdf::Namespace) do
      uri "http://example.org/"
      prefix "ex"
    end)
    stub_const("JsonLdTestModel", Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :description, :string

      rdf do
        namespace TestSkosNs, TestExNs

        subject { |m| "http://example.org/#{m.name}" } # rubocop:disable RSpec/NamedSubject

        type "skos:Concept"

        predicate :name, namespace: TestExNs, to: :name
        predicate :description, namespace: TestExNs, to: :description
      end
    end)
  end

  let(:instance) do
    JsonLdTestModel.new(name: "test", description: "A test concept")
  end

  describe "model_to_data" do
    let(:result) { instance.to_jsonld }

    it "generates @context with namespace prefixes" do
      parsed = JSON.parse(result)
      expect(parsed).to have_key("@context")
      expect(parsed["@context"]["skos"]).to eq("http://www.w3.org/2004/02/skos/core#")
      expect(parsed["@context"]["ex"]).to eq("http://example.org/")
    end

    it "generates @type as compact IRI" do
      parsed = JSON.parse(result)
      expect(parsed["@type"]).to eq("skos:Concept")
    end

    it "generates @id from subject block" do
      parsed = JSON.parse(result)
      expect(parsed["@id"]).to eq("http://example.org/test")
    end

    it "includes predicate data" do
      parsed = JSON.parse(result)
      expect(parsed["name"]).to eq("test")
      expect(parsed["description"]).to eq("A test concept")
    end
  end

  describe "model_to_data without type and subject" do
    before do
      stub_const("MinimalJsonLdModel", Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string

        rdf do
          namespace TestSkosNs

          predicate :notation, namespace: TestSkosNs, to: :value
        end
      end)
    end

    it "omits @type and @id when not defined" do
      instance = MinimalJsonLdModel.new(value: "x")
      parsed = JSON.parse(instance.to_jsonld)
      expect(parsed).not_to have_key("@type")
      expect(parsed).not_to have_key("@id")
      expect(parsed["notation"]).to eq("x")
    end
  end

  describe "data_to_model" do
    let(:jsonld_input) do
      {
        "@context" => { "ex" => "http://example.org/" },
        "@type" => "skos:Concept",
        "@id" => "http://example.org/test",
        "name" => "from_jsonld",
        "description" => "Loaded from JSON-LD",
      }
    end

    it "parses JSON-LD back to model" do
      model = JsonLdTestModel.from_jsonld(JSON.generate(jsonld_input))
      expect(model.name).to eq("from_jsonld")
      expect(model.description).to eq("Loaded from JSON-LD")
    end

    it "strips JSON-LD keywords before attribute mapping" do
      model = JsonLdTestModel.from_jsonld(JSON.generate(jsonld_input))
      expect(model).to be_a(JsonLdTestModel)
    end
  end

  describe "deserialization ignores JSON-LD keywords" do
    let(:jsonld_input) do
      {
        "@context" => { "ex" => "http://example.org/" },
        "@type" => "skos:Concept",
        "@id" => "http://example.org/test",
        "@graph" => [],
        "name" => "value_only",
      }
    end

    it "strips all @-prefixed keys" do
      model = JsonLdTestModel.from_jsonld(JSON.generate(jsonld_input))
      expect(model.name).to eq("value_only")
    end
  end

  describe "round-trip" do
    it "preserves data through model → JSON-LD → model" do
      json = instance.to_jsonld
      restored = JsonLdTestModel.from_jsonld(json)
      expect(restored.name).to eq("test")
      expect(restored.description).to eq("A test concept")
    end

    it "produces consistent @context through round-trip" do
      json = instance.to_jsonld
      parsed = JSON.parse(json)
      expect(parsed["@context"]["skos"]).to eq("http://www.w3.org/2004/02/skos/core#")
      expect(parsed["@context"]["ex"]).to eq("http://example.org/")
    end
  end

  describe "nil attribute values" do
    let(:instance) { JsonLdTestModel.new(name: "test", description: nil) }

    it "omits nil values from output" do
      parsed = JSON.parse(instance.to_jsonld)
      expect(parsed["name"]).to eq("test")
      expect(parsed).not_to have_key("description")
    end
  end

  describe "model with integer and boolean attributes" do
    before do
      stub_const("TypedJsonLdModel", Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
        attribute :count, :integer
        attribute :active, :boolean

        rdf do
          namespace TestSkosNs

          subject { |_| "http://example.org/1" } # rubocop:disable RSpec/NamedSubject

          type "skos:Concept"

          predicate :prefLabel, namespace: TestSkosNs, to: :label
          predicate :notation, namespace: TestSkosNs, to: :count
          predicate :note, namespace: TestSkosNs, to: :active
        end
      end)
    end

    it "serializes and deserializes typed values" do
      instance = TypedJsonLdModel.new(label: "test", count: 42, active: true)
      json = instance.to_jsonld
      parsed = JSON.parse(json)
      expect(parsed["notation"]).to eq(42)
      expect(parsed["note"]).to be(true)

      restored = TypedJsonLdModel.from_jsonld(json)
      expect(restored.count).to eq(42)
      expect(restored.active).to be(true)
    end
  end

  describe "collection attributes" do
    before do
      stub_const("CollectionJsonLdModel", Class.new(Lutaml::Model::Serializable) do
        attribute :tags, :string, collection: true

        rdf do
          namespace TestSkosNs

          subject { |_| "http://example.org/1" } # rubocop:disable RSpec/NamedSubject

          type "skos:Concept"

          predicate :notation, namespace: TestSkosNs, to: :tags
        end
      end)
    end

    it "round-trips collection values" do
      instance = CollectionJsonLdModel.new(tags: ["en", "fr"])
      json = instance.to_jsonld
      restored = CollectionJsonLdModel.from_jsonld(json)
      expect(restored.tags).to eq(["en", "fr"])
    end
  end
end
