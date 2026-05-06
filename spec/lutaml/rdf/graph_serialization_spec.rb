# frozen_string_literal: true

require "spec_helper"
require "lutaml/turtle"
require "lutaml/jsonld"

RSpec.describe "RDF graph-aware serialization" do
  before do
    stub_const("GraphTestNs", Class.new(Lutaml::Rdf::Namespace) do
      uri "http://example.org/"
      prefix "ex"
    end)

    stub_const("GraphMemberModel", Class.new(Lutaml::Model::Serializable) do
      attribute :code, :string
      attribute :name, :string

      rdf do
        namespace GraphTestNs

        type "ex:Item"
        predicate :notation, namespace: GraphTestNs, to: :code
        predicate :prefLabel, namespace: GraphTestNs, to: :name
      end
    end)

    stub_const("GraphContainerModel", Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string
      attribute :items, GraphMemberModel, collection: true

      rdf do
        namespace GraphTestNs
        subject { |m| "http://example.org/container/#{m.id}" } # rubocop:disable RSpec/NamedSubject

        type "ex:Container"
        predicate :prefLabel, namespace: GraphTestNs, to: :id
        members :items
      end
    end)
  end

  let(:first_item) { GraphMemberModel.new(code: "1", name: "First") }
  let(:second_item) { GraphMemberModel.new(code: "2", name: "Second") }
  let(:container) do
    GraphContainerModel.new(id: "test", items: [first_item, second_item])
  end

  describe "Turtle serialization with members" do
    subject(:turtle) { container.to_turtle }

    it "includes container triples" do
      expect(turtle).to include("a ex:Container")
      expect(turtle).to include("ex:container")
    end

    it "includes container predicates" do
      expect(turtle).to include('ex:prefLabel "test"')
    end

    it "includes all member blank nodes" do
      expect(turtle.scan("a ex:Item").length).to be >= 2
    end

    it "includes member types" do
      expect(turtle.scan("a ex:Item").length).to eq(2)
    end

    it "includes member predicates" do
      expect(turtle).to include('ex:notation "1"')
      expect(turtle).to include('ex:notation "2"')
      expect(turtle).to include('ex:prefLabel "First"')
      expect(turtle).to include('ex:prefLabel "Second"')
    end

    it "shares prefix declarations" do
      prefix_count = turtle.scan(/@prefix ex:/).length
      expect(prefix_count).to eq(1)
    end
  end

  describe "JSON-LD serialization with members" do
    subject(:jsonld) { JSON.parse(container.to_jsonld) }

    it "includes @context" do
      expect(jsonld["@context"]).to include("ex")
    end

    it "includes @graph array" do
      expect(jsonld["@graph"]).to be_an(Array)
      expect(jsonld["@graph"].length).to eq(3) # container + 2 items
    end

    it "includes container in @graph" do
      container_data = jsonld["@graph"].find do |r|
        r["@type"] == "ex:Container"
      end
      expect(container_data).not_to be_nil
      expect(container_data["@id"]).to eq("http://example.org/container/test")
      expect(container_data["prefLabel"]).to eq("test")
    end

    it "includes all members in @graph" do
      items = jsonld["@graph"].select { |r| r["@type"] == "ex:Item" }
      expect(items.length).to eq(2)
      codes = items.map { |i| i["notation"] }
      expect(codes).to contain_exactly("1", "2")
    end
  end

  describe "container without subject (member-only)" do
    before do
      stub_const("MemberOnlyModel", Class.new(Lutaml::Model::Serializable) do
        attribute :items, GraphMemberModel, collection: true

        rdf do
          namespace GraphTestNs
          members :items
        end
      end)
    end

    let(:model) { MemberOnlyModel.new(items: [first_item, second_item]) }

    it "serializes only member triples to turtle" do
      turtle = model.to_turtle
      expect(turtle).to include("a ex:Item")
      expect(turtle).not_to include("ex:Container")
    end

    it "serializes only members to jsonld @graph" do
      jsonld = JSON.parse(model.to_jsonld)
      expect(jsonld["@graph"].length).to eq(2)
      items = jsonld["@graph"].select { |r| r["@type"] == "ex:Item" }
      expect(items.length).to eq(2)
    end
  end
end
