# frozen_string_literal: true

require "spec_helper"
require "lutaml/turtle"

RSpec.describe Lutaml::Turtle::Transform do
  before do
    stub_const("TurtleTestModel", Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :description, :string
      attribute :code, :string

      turtle do
        namespace Lutaml::Rdf::Namespaces::SkosNamespace,
                  Lutaml::Rdf::Namespaces::DctermsNamespace

        subject { |m| "http://example.org/concept/#{m.code}" }

        type "skos:Concept"

        predicate :prefLabel,
                  namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                  to: :name,
                  lang_tagged: true

        predicate :definition,
                  namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                  to: :description

        predicate :notation,
                  namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                  to: :code
      end
    end)
  end

  let(:instance) do
    TurtleTestModel.new(name: "test concept",
                        description: "A test description",
                        code: "2119")
  end

  describe "model_to_data" do
    let(:result) { instance.to_turtle }

    it "generates prefix declarations for used namespaces" do
      expect(result).to include("@prefix skos: <http://www.w3.org/2004/02/skos/core#>")
    end

    it "generates subject URI" do
      expect(result).to include("<http://example.org/concept/2119>")
    end

    it "generates rdf:type triple using compact prefix" do
      expect(result).to include("a skos:Concept")
    end

    it "generates predicate triples" do
      expect(result).to include("skos:notation \"2119\"")
      expect(result).to include("skos:definition \"A test description\"")
    end

    it "terminates with a period" do
      expect(result.strip).to end_with(".")
    end
  end

  describe "special character escaping" do
    let(:instance) do
      TurtleTestModel.new(name: "has \"quotes\" and\nnewlines",
                          description: "back\\slash",
                          code: "1")
    end

    it "escapes double quotes in literals" do
      result = instance.to_turtle
      expect(result).to include('\\"quotes\\"')
    end

    it "handles multiline literals via triple-quoted strings" do
      result = instance.to_turtle
      expect(result).to include("has")
      expect(result).to include("newlines")
    end

    it "escapes backslashes in literals" do
      result = instance.to_turtle
      expect(result).to include("back\\\\slash")
    end
  end

  describe "numeric and boolean values" do
    before do
      stub_const("TypedModel", Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
        attribute :count, :integer
        attribute :active, :boolean

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace

          subject { |_| "http://example.org/1" }

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :label

          predicate :notation,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :count

          predicate :note,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :active
        end
      end)
    end

    it "serializes integers as native Turtle literals" do
      instance = TypedModel.new(label: "test", count: 42, active: true)
      result = instance.to_turtle
      expect(result).to match(/skos:notation 42/)
    end

    it "serializes booleans as native Turtle literals" do
      instance = TypedModel.new(label: "test", count: 1, active: true)
      result = instance.to_turtle
      expect(result).to match(/skos:note true/)
    end
  end

  describe "model without subject" do
    before do
      stub_const("NoSubjectModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace
          type "skos:Concept"
          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :name
        end
      end)
    end

    it "raises MissingSubjectError" do
      instance = NoSubjectModel.new(name: "test")
      expect { instance.to_turtle }
        .to raise_error(Lutaml::Turtle::MissingSubjectError)
    end
  end

  describe "model with nil values" do
    let(:instance) { TurtleTestModel.new(name: "test", code: "2119") }

    it "omits predicates for nil attributes" do
      result = instance.to_turtle
      expect(result).not_to include("definition")
      expect(result).to include("prefLabel")
    end
  end

  describe "model with no predicates producing data" do
    before do
      stub_const("EmptyPredModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace

          subject { |m| "http://example.org/#{m.name}" }

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :name
        end
      end)
    end

    let(:instance) { EmptyPredModel.new(name: nil) }

    it "returns empty string when no data" do
      expect(instance.to_turtle).to eq("")
    end
  end

  describe "collection predicates" do
    before do
      stub_const("CollectionModel", Class.new(Lutaml::Model::Serializable) do
        attribute :labels, :string, collection: true

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace

          subject { |_| "http://example.org/1" }

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :labels
        end
      end)
    end

    it "generates triples for all collection values" do
      instance = CollectionModel.new(labels: ["en", "fr"])
      result = instance.to_turtle
      expect(result).to include('"en"')
      expect(result).to include('"fr"')
      expect(result).to include("skos:prefLabel")
    end
  end

  describe "full URI type (no prefix)" do
    before do
      stub_const("FullUriTypeModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace

          subject { |m| "http://example.org/#{m.name}" }

          type "http://example.org/MyType"

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :name
        end
      end)
    end

    it "uses full URI as-is when no colon prefix" do
      instance = FullUriTypeModel.new(name: "test")
      result = instance.to_turtle
      expect(result).to include("<http://example.org/MyType>")
    end
  end

  describe "data_to_model (deserialization)" do
    let(:turtle_input) do
      <<~TURTLE
        @prefix skos: <http://www.w3.org/2004/02/skos/core#> .
        @prefix dcterms: <http://purl.org/dc/terms/> .

        <http://example.org/concept/2119> a skos:Concept ;
          skos:prefLabel "test concept"@en ;
          skos:definition "A test description" ;
          skos:notation "2119" .
      TURTLE
    end

    it "deserializes string attributes" do
      model = TurtleTestModel.from_turtle(turtle_input)
      expect(model.code).to eq("2119")
      expect(model.description).to eq("A test description")
    end

    it "deserializes language-tagged values" do
      model = TurtleTestModel.from_turtle(turtle_input)
      expect(model.name).to eq("test concept")
    end
  end

  describe "round-trip" do
    it "preserves data through model → Turtle → model" do
      turtle = instance.to_turtle
      restored = TurtleTestModel.from_turtle(turtle)
      expect(restored.code).to eq("2119")
      expect(restored.description).to eq("A test description")
    end
  end
end
