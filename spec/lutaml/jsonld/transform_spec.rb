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

  describe "multiple types" do
    before do
      stub_const("DctermsTestNs", Class.new(Lutaml::Rdf::Namespace) do
        uri "http://purl.org/dc/terms/"
        prefix "dcterms"
      end)

      stub_const("MultiTypeJsonLdModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        rdf do
          namespace TestSkosNs, DctermsTestNs

          subject { |m| "http://example.org/#{m.name}" } # rubocop:disable RSpec/NamedSubject

          type ["skos:Concept", "dcterms:Agent"]

          predicate :name, namespace: TestExNs, to: :name
        end
      end)
    end

    it "generates @type as array for multiple types" do
      instance = MultiTypeJsonLdModel.new(name: "multi")
      parsed = JSON.parse(instance.to_jsonld)
      expect(parsed["@type"]).to eq(["skos:Concept", "dcterms:Agent"])
    end

    it "generates @type as string for single type" do
      instance = JsonLdTestModel.new(name: "single")
      parsed = JSON.parse(instance.to_jsonld)
      expect(parsed["@type"]).to eq("skos:Concept")
    end
  end

  describe "URI reference predicates" do
    before do
      stub_const("UriRefJsonLdModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :related, :string, collection: true

        rdf do
          namespace TestSkosNs, TestExNs

          subject { |m| "http://example.org/#{m.name}" } # rubocop:disable RSpec/NamedSubject

          type "skos:Concept"

          predicate :name, namespace: TestExNs, to: :name
          predicate :related, namespace: TestSkosNs, to: :related,
                              uri_reference: true
        end
      end)
    end

    it "generates @type @id in context for uri_reference predicates" do
      instance = UriRefJsonLdModel.new(name: "test", related: ["skos:other"])
      parsed = JSON.parse(instance.to_jsonld)
      expect(parsed["@context"]["related"]).to eq({
                                                    "@id" => "http://www.w3.org/2004/02/skos/core#related",
                                                    "@type" => "@id",
                                                  })
    end

    it "serializes URI reference as @id object" do
      instance = UriRefJsonLdModel.new(name: "test", related: ["skos:other"])
      parsed = JSON.parse(instance.to_jsonld)
      expect(parsed["related"]).to eq([{ "@id" => "skos:other" }])
    end

    it "serializes single URI reference value as @id object" do
      stub_const("SingleUriRefModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :link, :string

        rdf do
          namespace TestSkosNs, TestExNs

          subject { |m| "http://example.org/#{m.name}" } # rubocop:disable RSpec/NamedSubject

          type "skos:Concept"

          predicate :name, namespace: TestExNs, to: :name
          predicate :related, namespace: TestSkosNs, to: :link,
                              uri_reference: true
        end
      end)

      instance = SingleUriRefModel.new(name: "test", link: "skos:something")
      parsed = JSON.parse(instance.to_jsonld)
      expect(parsed["related"]).to eq({ "@id" => "skos:something" })
    end
  end

  describe "member linking predicates" do
    before do
      stub_const("JsonLdChildModel", Class.new(Lutaml::Model::Serializable) do
        attribute :cid, :string
        attribute :label, :string

        rdf do
          namespace TestSkosNs, TestExNs

          subject { |m| "http://example.org/item/#{m.cid}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "skos:Concept"

          predicate :prefLabel, namespace: TestSkosNs, to: :label
        end
      end)

      stub_const("JsonLdParentModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :children, JsonLdChildModel, collection: true

        rdf do
          namespace TestSkosNs, TestExNs

          subject { |m| "http://example.org/group/#{m.name}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "skos:Collection"

          predicate :prefLabel, namespace: TestSkosNs, to: :name

          members :children,
                  predicate_name: :member,
                  namespace: TestSkosNs
        end
      end)
    end

    it "includes linking term in @context with @type @id" do
      parent = JsonLdParentModel.new(
        name: "grp1",
        children: [JsonLdChildModel.new(cid: "a", label: "Alpha")],
      )
      parsed = JSON.parse(parent.to_jsonld)
      expect(parsed["@context"]["member"]).to eq({
                                                   "@id" => "http://www.w3.org/2004/02/skos/core#member",
                                                   "@type" => "@id",
                                                 })
    end

    it "generates @id references for linked members in @graph" do
      parent = JsonLdParentModel.new(
        name: "grp1",
        children: [
          JsonLdChildModel.new(cid: "a", label: "Alpha"),
          JsonLdChildModel.new(cid: "b", label: "Beta"),
        ],
      )
      parsed = JSON.parse(parent.to_jsonld)
      parent_resource = parsed["@graph"].find { |r| r["@type"] }
      expect(parent_resource["member"]).to eq([
                                                { "@id" => "http://example.org/item/a" },
                                                { "@id" => "http://example.org/item/b" },
                                              ])
    end

    it "includes member resources in @graph" do
      parent = JsonLdParentModel.new(
        name: "grp1",
        children: [JsonLdChildModel.new(cid: "a", label: "Alpha")],
      )
      parsed = JSON.parse(parent.to_jsonld)
      member = parsed["@graph"].find { |r| r["prefLabel"] == "Alpha" }
      expect(member).not_to be_nil
      expect(member["@id"]).to eq("http://example.org/item/a")
    end

    it "merges child namespaces into @context" do
      parent = JsonLdParentModel.new(
        name: "grp1",
        children: [JsonLdChildModel.new(cid: "a", label: "Alpha")],
      )
      parsed = JSON.parse(parent.to_jsonld)
      expect(parsed["@context"]["skos"]).to eq("http://www.w3.org/2004/02/skos/core#")
      expect(parsed["@context"]["ex"]).to eq("http://example.org/")
    end

    it "omits linking key when members have no linking predicate" do
      stub_const("UnlinkedChild", Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string

        rdf do
          namespace TestSkosNs

          subject { |m| "http://example.org/#{m.label}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          predicate :prefLabel, namespace: TestSkosNs, to: :label
        end
      end)

      stub_const("UnlinkedParent", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :items, UnlinkedChild, collection: true

        rdf do
          namespace TestSkosNs

          subject { |m| "http://example.org/#{m.name}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          predicate :prefLabel, namespace: TestSkosNs, to: :name

          members :items
        end
      end)

      parent = UnlinkedParent.new(
        name: "grp",
        items: [UnlinkedChild.new(label: "a")],
      )
      parsed = JSON.parse(parent.to_jsonld)
      expect(parsed["@context"]).not_to have_key("member")
    end
  end

  describe "empty type array" do
    before do
      stub_const("NoTypeJsonLdModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        rdf do
          namespace TestExNs

          subject { |m| "http://example.org/#{m.name}" } # rubocop:disable RSpec/NamedSubject

          predicate :name, namespace: TestExNs, to: :name
        end
      end)
    end

    it "omits @type when no types declared" do
      instance = NoTypeJsonLdModel.new(name: "test")
      parsed = JSON.parse(instance.to_jsonld)
      expect(parsed).not_to have_key("@type")
    end
  end

  describe "dynamic link predicates (String)" do
    before do
      stub_const("JsonLdDynChild", Class.new(Lutaml::Model::Serializable) do
        attribute :cid, :string
        attribute :label, :string

        rdf do
          namespace TestSkosNs, TestExNs

          subject { |m| "http://example.org/item/#{m.cid}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "skos:Concept"

          predicate :prefLabel, namespace: TestSkosNs, to: :label
        end
      end)

      stub_const("JsonLdDynParent", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :children, JsonLdDynChild, collection: true

        rdf do
          namespace TestSkosNs, TestExNs

          subject { |m| "http://example.org/group/#{m.name}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "skos:Collection"

          predicate :prefLabel, namespace: TestSkosNs, to: :name

          members :children, link: "skos:member"
        end
      end)
    end

    it "generates @id references for linked members" do
      parent = JsonLdDynParent.new(
        name: "grp1",
        children: [
          JsonLdDynChild.new(cid: "a", label: "Alpha"),
          JsonLdDynChild.new(cid: "b", label: "Beta"),
        ],
      )
      parsed = JSON.parse(parent.to_jsonld)
      parent_resource = parsed["@graph"].find { |r| r["@type"] == "skos:Collection" }
      expect(parent_resource["member"]).to eq([
                                                { "@id" => "http://example.org/item/a" },
                                                { "@id" => "http://example.org/item/b" },
                                              ])
    end

    it "includes member resources in @graph" do
      parent = JsonLdDynParent.new(
        name: "grp1",
        children: [JsonLdDynChild.new(cid: "a", label: "Alpha")],
      )
      parsed = JSON.parse(parent.to_jsonld)
      member = parsed["@graph"].find { |r| r["prefLabel"] == "Alpha" }
      expect(member).not_to be_nil
    end
  end

  describe "recursive context and resource collection" do
    before do
      stub_const("JsonLdLeaf", Class.new(Lutaml::Model::Serializable) do
        attribute :value, :string
        attribute :lid, :string

        rdf do
          namespace TestExNs

          subject { |m| "http://example.org/leaf/#{m.lid}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "ex:Leaf"

          predicate :name, namespace: TestExNs, to: :value
        end
      end)

      stub_const("JsonLdMid", Class.new(Lutaml::Model::Serializable) do
        attribute :label, :string
        attribute :mid, :string
        attribute :leaves, JsonLdLeaf, collection: true

        rdf do
          namespace TestSkosNs, TestExNs

          subject { |m| "http://example.org/mid/#{m.mid}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "skos:Concept"

          predicate :prefLabel, namespace: TestSkosNs, to: :label

          members :leaves, link: "skos:member"
        end
      end)

      stub_const("JsonLdRoot", Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
        attribute :mids, JsonLdMid, collection: true

        rdf do
          namespace TestSkosNs

          subject { |m| "http://example.org/root/#{m.title}" } # rubocop:disable RSpec/NamedSubject, RSpec/MultipleSubjects

          type "skos:Collection"

          predicate :prefLabel, namespace: TestSkosNs, to: :title

          members :mids, link: "skos:member"
        end
      end)
    end

    it "collects @context from all nesting levels" do
      root = JsonLdRoot.new(
        title: "r1",
        mids: [JsonLdMid.new(
          label: "m1",
          mid: "a",
          leaves: [JsonLdLeaf.new(value: "l1", lid: "x")],
        )],
      )
      parsed = JSON.parse(root.to_jsonld)
      expect(parsed["@context"]["skos"]).to eq("http://www.w3.org/2004/02/skos/core#")
      expect(parsed["@context"]["ex"]).to eq("http://example.org/")
    end

    it "includes resources from all nesting levels in @graph" do
      root = JsonLdRoot.new(
        title: "r1",
        mids: [JsonLdMid.new(
          label: "m1",
          mid: "a",
          leaves: [JsonLdLeaf.new(value: "l1", lid: "x")],
        )],
      )
      parsed = JSON.parse(root.to_jsonld)
      graph = parsed["@graph"]
      types = graph.map { |r| r["@type"] }
      expect(types).to include("skos:Collection")
      expect(types).to include("skos:Concept")
      expect(types).to include("ex:Leaf")
    end
  end
end
