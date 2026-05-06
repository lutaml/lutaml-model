# frozen_string_literal: true

require "spec_helper"
require "lutaml/turtle"
require "lutaml/jsonld"

RSpec.describe "Round-trip fidelity" do
  before do
    stub_const("TestSkosNs", Class.new(Lutaml::Rdf::Namespace) do
      uri "http://www.w3.org/2004/02/skos/core#"
      prefix "skos"
    end)

    stub_const("TestExNs", Class.new(Lutaml::Rdf::Namespace) do
      uri "http://example.org/"
      prefix "ex"
    end)
  end

  describe "Turtle round-trip" do
    before do
      stub_const("RtTurtleModel", Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
        attribute :note, :string
        attribute :code, :integer

        turtle do
          namespace TestSkosNs

          subject { |m| "http://example.org/item/#{m.code}" } # rubocop:disable RSpec/NamedSubject

          type "skos:Concept"
          predicate :prefLabel,
                    namespace: TestSkosNs,
                    to: :label
          predicate :note,
                    namespace: TestSkosNs,
                    to: :note
          predicate :notation,
                    namespace: TestSkosNs,
                    to: :code
        end
      end)
    end

    it "preserves string and integer attributes" do
      original = RtTurtleModel.new(label: "hello", note: "world", code: 99)
      turtle = original.to_turtle
      restored = RtTurtleModel.from_turtle(turtle)
      expect(restored.label).to eq("hello")
      expect(restored.note).to eq("world")
      expect(restored.code).to eq(99)
    end

    it "handles special characters in string values" do
      original = RtTurtleModel.new(label: 'say "hi"', note: "line1\nline2",
                                   code: 1)
      turtle = original.to_turtle
      restored = RtTurtleModel.from_turtle(turtle)
      expect(restored.label).to eq('say "hi"')
      expect(restored.note).to eq("line1\nline2")
    end

    it "handles nil optional attributes" do
      original = RtTurtleModel.new(label: "test", note: nil, code: 1)
      turtle = original.to_turtle
      restored = RtTurtleModel.from_turtle(turtle)
      expect(restored.label).to eq("test")
      expect(restored.note).to be_nil
      expect(restored.code).to eq(1)
    end
  end

  describe "JSON-LD round-trip" do
    before do
      stub_const("RtJsonLdModel", Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
        attribute :body, :string
        attribute :priority, :integer

        rdf do
          namespace TestExNs

          subject { |m| "http://example.org/articles/#{m.priority}" } # rubocop:disable RSpec/NamedSubject

          type "http://example.org/Article"

          predicate :title, namespace: TestExNs, to: :title
          predicate :body, namespace: TestExNs, to: :body
          predicate :priority, namespace: TestExNs, to: :priority
        end
      end)
    end

    it "preserves all attributes through serialize → deserialize" do
      original = RtJsonLdModel.new(title: "Test", body: "Content", priority: 5)
      json = original.to_jsonld
      restored = RtJsonLdModel.from_jsonld(json)
      expect(restored.title).to eq("Test")
      expect(restored.body).to eq("Content")
      expect(restored.priority).to eq(5)
    end

    it "preserves @context structure across round-trip" do
      original = RtJsonLdModel.new(title: "Test", body: "Content", priority: 1)
      json1 = original.to_jsonld
      restored = RtJsonLdModel.from_jsonld(json1)
      json2 = restored.to_jsonld

      ctx1 = JSON.parse(json1)["@context"]
      ctx2 = JSON.parse(json2)["@context"]
      expect(ctx1).to eq(ctx2)
    end

    it "handles nil optional attributes" do
      original = RtJsonLdModel.new(title: "Test", body: nil, priority: 1)
      json = original.to_jsonld
      restored = RtJsonLdModel.from_jsonld(json)
      expect(restored.title).to eq("Test")
      expect(restored.body).to be_nil
    end
  end

  describe "Error handling" do
    it "Turtle raises MissingSubjectError without subject" do
      stub_const("NoSubjModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        turtle do
          namespace TestSkosNs
          type "skos:Concept"
          predicate :prefLabel,
                    namespace: TestSkosNs,
                    to: :name
        end
      end)

      expect { NoSubjModel.new(name: "test").to_turtle }
        .to raise_error(Lutaml::Turtle::MissingSubjectError, /subject/)
    end

    it "JSON-LD handles invalid JSON gracefully" do
      stub_const("SimpleJsonLdModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        rdf do
          namespace TestExNs
          predicate :name, namespace: TestExNs, to: :name
        end
      end)

      expect { SimpleJsonLdModel.from_jsonld("not valid json!!!") }
        .to raise_error(Lutaml::Model::InvalidFormatError)
    end

    it "Rdf::MappingRule validates namespace type" do
      mapping = Lutaml::Rdf::Mapping.new
      expect do
        mapping.predicate(:foo, namespace: String, to: :bar)
      end.to raise_error(ArgumentError, /Rdf::Namespace/)
    end

    it "Rdf::MappingRule requires :to parameter" do
      mapping = Lutaml::Rdf::Mapping.new
      expect do
        mapping.predicate(:foo, namespace: TestSkosNs, to: nil)
      end.to raise_error(ArgumentError, /required/)
    end
  end
end
