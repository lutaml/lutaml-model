# frozen_string_literal: true

require "json"
require "yaml"

require "spec_helper"

RSpec.describe "JSON/YAML schema generation regressions (#863, #864, #865, #866)" do
  before do
    stub_const("SchemaRepro::Node", node_class)
    stub_const("SchemaRepro::Outer", outer_class)
    stub_const("SchemaRepro::Relation", relation_class)
    stub_const("SchemaRepro::Simple", simple_class)
  end

  let(:node_class) do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      xml { element "Node" }
    end
    klass.attribute :child, klass
    klass
  end

  let(:outer_class) do
    Class.new(Lutaml::Model::Serializable) do
      choice(min: 1, max: 1) do
        choice(min: 1, max: 1) do
          attribute :from, :string
          attribute :to, :string
        end
        attribute :at, :string
      end
      xml { element "Outer" }
    end
  end

  let(:relation_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :type, :string
      choice(min: 1, max: 1) do
        attribute :locality, :string, collection: true, initialize_empty: true
        attribute :locality_stack, :string, collection: true, initialize_empty: true
      end
      choice(min: 1, max: 1) do
        attribute :source_locality, :string, collection: true, initialize_empty: true
        attribute :source_locality_stack, :string, collection: true, initialize_empty: true
      end
      xml { element "Relation" }
    end
  end

  let(:simple_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :x, :string
      xml { element "Simple" }
    end
  end

  describe "#863: recursive models" do
    it "terminates and emits one definition per class" do
      schema = JSON.parse(Lutaml::Model::Schema.to_json(SchemaRepro::Node))
      expect(schema["$defs"].keys).to contain_exactly("SchemaRepro_Node")
    end

    it "generates through the YAML path" do
      yaml = Lutaml::Model::Schema.to_yaml(SchemaRepro::Node)
      expect(YAML.safe_load(yaml)).to include("$defs")
    end
  end

  describe "#864: nested choice blocks" do
    it "collapses the nested group into the outer at-most-one set" do
      schema = JSON.parse(Lutaml::Model::Schema.to_json(SchemaRepro::Outer))
      one_of = schema["$defs"]["SchemaRepro_Outer"]["oneOf"]
      requireds = one_of.map { |b| b["allOf"].to_a.filter_map { |s| s["required"]&.first } }
      expect(requireds).to contain_exactly([], %w[from], %w[to], %w[at])
    end
  end

  describe "#865: independent choices combine conjunctively" do
    it "renders an allOf of oneOf at-most-one groups" do
      schema = JSON.parse(Lutaml::Model::Schema.to_json(SchemaRepro::Relation))
      all_of = schema["$defs"]["SchemaRepro_Relation"]["allOf"]
      expect(all_of.length).to eq(2)
      all_of.each do |group|
        expect(group).to have_key("oneOf")
        expect(group["oneOf"].length).to eq(3)
      end
    end
  end

  describe "#869: the serializer's own output validates" do
    it "emits no required keys for initialize_empty choice members" do
      schema = JSON.parse(Lutaml::Model::Schema.to_json(SchemaRepro::Relation))
      definition = schema["$defs"]["SchemaRepro_Relation"]
      groups = definition["allOf"] || [definition]
      groups.each do |group|
        group["oneOf"].each do |branch|
          Array(branch["allOf"]).each do |sub|
            expect(sub).not_to have_key("required") if sub.key?("not")
          end
        end
      end
    end

    it "accepts the document the default instance serializes to" do
      inst = SchemaRepro::Relation.new(type: "includes")
      doc = inst.to_hash
      expect(doc).to eq("type" => "includes")
      schema = JSON.parse(Lutaml::Model::Schema.to_json(SchemaRepro::Relation))
      definition = schema["$defs"]["SchemaRepro_Relation"]
      groups = definition["allOf"] || [definition]
      groups.each do |group|
        satisfied = group["oneOf"].count do |branch|
          Array(branch["allOf"]).all? do |sub|
            if sub.key?("not")
              Array(sub["not"]["anyOf"]).none? do |req|
                doc.key?(req["required"].first)
              end
            else
              doc.key?(sub["required"].first)
            end
          end
        end
        expect(satisfied).to eq(1)
      end
    end
  end

  describe "#866: Schema.to_json / to_yaml delegation" do
    it "accepts a positional options hash" do
      expect { Lutaml::Model::Schema.to_json(SchemaRepro::Simple) }
        .not_to raise_error
      expect { Lutaml::Model::Schema.to_yaml(SchemaRepro::Simple) }
        .not_to raise_error
    end
  end
end
