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
      expect(result).to include("skos:notation 42")
    end

    it "serializes booleans as native Turtle literals" do
      instance = TypedModel.new(label: "test", count: 1, active: true)
      result = instance.to_turtle
      expect(result).to include("skos:note true")
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

    it "round-trips deserialized data back to Turtle" do
      model = TurtleTestModel.from_turtle(turtle_input)
      turtle_out = model.to_turtle
      expect(turtle_out).to include("skos:Concept")
      expect(turtle_out).to include("skos:notation \"2119\"")
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

  describe "multiple types" do
    before do
      stub_const("DualTypeModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace,
                    Lutaml::Rdf::Namespaces::DctermsNamespace

          subject { |m| "http://example.org/#{m.name}" }

          type ["skos:Concept", "dcterms:Agent"]

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :name
        end
      end)
    end

    it "generates multiple rdf:type triples" do
      instance = DualTypeModel.new(name: "test")
      result = instance.to_turtle
      expect(result).to include("a skos:Concept")
      expect(result).to include("dcterms:Agent")
    end

    it "round-trips multiple types" do
      instance = DualTypeModel.new(name: "test")
      turtle = instance.to_turtle
      restored = DualTypeModel.from_turtle(turtle)
      expect(restored.name).to eq("test")
    end
  end

  describe "empty type array" do
    before do
      stub_const("NoTypeModel", Class.new(Lutaml::Model::Serializable) do
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

    it "omits rdf:type when no types declared" do
      instance = NoTypeModel.new(name: "test")
      result = instance.to_turtle
      expect(result).not_to include(" a ")
      expect(result).to include("skos:prefLabel")
    end
  end

  describe "URI reference predicates" do
    before do
      stub_const("UriRefModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :related, :string, collection: true

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace,
                    Lutaml::Rdf::Namespaces::DctermsNamespace

          subject { |m| "http://example.org/#{m.name}" }

          type "skos:Concept"

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :name

          predicate :related,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :related,
                    uri_reference: true
        end
      end)
    end

    it "emits URI objects instead of literals" do
      instance = UriRefModel.new(name: "test", related: ["skos:other"])
      result = instance.to_turtle
      expect(result).to include("skos:related skos:other")
      expect(result).not_to include('"skos:other"')
    end

    it "round-trips URI references preserving compact form" do
      instance = UriRefModel.new(name: "test", related: ["skos:other"])
      turtle = instance.to_turtle
      restored = UriRefModel.from_turtle(turtle)
      expect(restored.related).to eq(["skos:other"])
    end

    it "handles full URI values without prefix" do
      instance = UriRefModel.new(name: "test",
                                 related: ["http://example.org/foo"])
      result = instance.to_turtle
      expect(result).to include("skos:related <http://example.org/foo>")
    end

    it "round-trips full URI values as-is" do
      instance = UriRefModel.new(name: "test",
                                 related: ["http://example.org/foo"])
      turtle = instance.to_turtle
      restored = UriRefModel.from_turtle(turtle)
      expect(restored.related).to eq(["http://example.org/foo"])
    end
  end

  describe "member linking predicates" do
    before do
      stub_const("ChildModel", Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
        attribute :cid, :string

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace

          subject { |m| "http://example.org/child/#{m.cid}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "skos:Concept"

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :label
        end
      end)

      stub_const("ParentModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :children, ChildModel, collection: true

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace

          subject { |m| "http://example.org/parent/#{m.name}" }

          type "skos:Collection"

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :name

          members :children,
                  predicate_name: :member,
                  namespace: Lutaml::Rdf::Namespaces::SkosNamespace
        end
      end)
    end

    it "generates linking triples from parent to members" do
      parent = ParentModel.new(
        name: "parent1",
        children: [
          ChildModel.new(label: "child1", cid: "c1"),
          ChildModel.new(label: "child2", cid: "c2"),
        ],
      )
      result = parent.to_turtle
      expect(result).to include("skos:member <http://example.org/child/c1>")
      expect(result).to include("<http://example.org/child/c2>")
    end

    it "still generates member graph nodes" do
      parent = ParentModel.new(
        name: "parent1",
        children: [
          ChildModel.new(label: "child1", cid: "c1"),
        ],
      )
      result = parent.to_turtle
      expect(result).to include("skos:prefLabel \"child1\"")
    end
  end

  describe "linked-only model (no type, no predicates)" do
    before do
      stub_const("LinkedOnlyChild", Class.new(Lutaml::Model::Serializable) do
        attribute :cid, :string
        attribute :label, :string

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace

          subject { |m| "http://example.org/item/#{m.cid}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "skos:Concept"

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :label
        end
      end)

      stub_const("LinkedOnlyParent", Class.new(Lutaml::Model::Serializable) do
        attribute :pid, :string
        attribute :items, LinkedOnlyChild, collection: true

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace

          subject { |m| "http://example.org/group/#{m.pid}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          members :items,
                  predicate_name: :member,
                  namespace: Lutaml::Rdf::Namespaces::SkosNamespace
        end
      end)
    end

    it "generates linking triples even without type or predicates" do
      parent = LinkedOnlyParent.new(
        pid: "g1",
        items: [
          LinkedOnlyChild.new(cid: "a", label: "Alpha"),
          LinkedOnlyChild.new(cid: "b", label: "Beta"),
        ],
      )
      result = parent.to_turtle
      expect(result).to include("skos:member")
      expect(result).to include("<http://example.org/item/a>")
      expect(result).to include("<http://example.org/item/b>")
    end

    it "includes member subgraph data" do
      parent = LinkedOnlyParent.new(
        pid: "g1",
        items: [LinkedOnlyChild.new(cid: "a", label: "Alpha")],
      )
      result = parent.to_turtle
      expect(result).to include("skos:prefLabel \"Alpha\"")
    end

    it "does not generate rdf:type for parent" do
      parent = LinkedOnlyParent.new(
        pid: "g1",
        items: [LinkedOnlyChild.new(cid: "a", label: "Alpha")],
      )
      result = parent.to_turtle
      parent_line = result.lines.find { |l| l.include?("<http://example.org/group/g1>") }
      expect(parent_line).not_to include(" a ")
    end
  end

  describe "heterogeneous member collection" do
    before do
      stub_const("HeteroChildA", Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace

          subject { |m| "http://example.org/a/#{m.label}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "skos:Concept"

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :label
        end
      end)

      stub_const("HeteroChildB", Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string

        turtle do
          namespace Lutaml::Rdf::Namespaces::DctermsNamespace

          subject { |m| "http://example.org/b/#{m.title}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "dcterms:Agent"

          predicate :title,
                    namespace: Lutaml::Rdf::Namespaces::DctermsNamespace,
                    to: :title
        end
      end)

      stub_const("HeteroParent", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :items, :string, collection: true

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace

          subject { |m| "http://example.org/parent/#{m.name}" }

          type "skos:Collection"

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :name
        end
      end)
    end

    it "includes prefixes from all member types" do
      skip "Heterogeneous collection requires union-typed attribute (not yet supported)"
    end
  end

  describe "dynamic link predicates" do
    before do
      stub_const("DynChild", Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
        attribute :cid, :string

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace

          subject { |m| "http://example.org/child/#{m.cid}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "skos:Concept"

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :label
        end
      end)

      stub_const("DynParent", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :children, DynChild, collection: true

        turtle do
          namespace Lutaml::Rdf::Namespaces::SkosNamespace

          subject { |m| "http://example.org/parent/#{m.name}" }

          type "skos:Collection"

          predicate :prefLabel,
                    namespace: Lutaml::Rdf::Namespaces::SkosNamespace,
                    to: :name

          members :children, link: "skos:member"
        end
      end)
    end

    it "generates linking triples from String link" do
      parent = DynParent.new(
        name: "p1",
        children: [DynChild.new(label: "c1", cid: "a")],
      )
      result = parent.to_turtle
      expect(result).to include("skos:member <http://example.org/child/a>")
    end

    it "includes child subgraph data" do
      parent = DynParent.new(
        name: "p1",
        children: [DynChild.new(label: "c1", cid: "a")],
      )
      result = parent.to_turtle
      expect(result).to include("skos:prefLabel \"c1\"")
    end
  end

  describe "recursive prefix collection" do
    before do
      stub_const("SkosNs", Lutaml::Rdf::Namespaces::SkosNamespace)
      stub_const("DctermsNs", Lutaml::Rdf::Namespaces::DctermsNamespace)

      stub_const("LeafModel", Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string
        attribute :lid, :string

        turtle do
          namespace DctermsNs

          subject { |m| "http://example.org/leaf/#{m.lid}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "dcterms:Agent"

          predicate :title, namespace: DctermsNs, to: :value
        end
      end)

      stub_const("MidModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :mid, :string
        attribute :leaves, LeafModel, collection: true

        turtle do
          namespace SkosNs, DctermsNs

          subject { |m| "http://example.org/mid/#{m.mid}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "skos:Concept"

          predicate :prefLabel, namespace: SkosNs, to: :name

          members :leaves, link: "skos:member"
        end
      end)

      stub_const("RootModel", Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
        attribute :mids, MidModel, collection: true

        turtle do
          namespace SkosNs

          subject { |m| "http://example.org/root/#{m.title}" }

          type "skos:Collection"

          predicate :prefLabel, namespace: SkosNs, to: :title

          members :mids, link: "skos:member"
        end
      end)
    end

    it "collects prefixes from all nesting levels" do
      root = RootModel.new(
        title: "r1",
        mids: [MidModel.new(
          name: "m1",
          mid: "a",
          leaves: [LeafModel.new(value: "l1", lid: "x")],
        )],
      )
      result = root.to_turtle
      expect(result).to include("@prefix skos:")
      expect(result).to include("@prefix dcterms:")
    end

    it "emits triples from all nesting levels" do
      root = RootModel.new(
        title: "r1",
        mids: [MidModel.new(
          name: "m1",
          mid: "a",
          leaves: [LeafModel.new(value: "l1", lid: "x")],
        )],
      )
      result = root.to_turtle
      expect(result).to include("skos:prefLabel \"r1\"")
      expect(result).to include("skos:prefLabel \"m1\"")
      expect(result).to include("dcterms:title \"l1\"")
    end
  end
end
