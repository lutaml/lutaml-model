# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"

RSpec.describe Lutaml::Lml::DocumentBuilder do
  let(:registry) { described_class.default_registry }
  let(:builder) { described_class.new(registry) }

  describe "#build" do
    it "creates a document from a hash" do
      doc = builder.build(:document, { title: "Test" })
      expect(doc).to be_a(Lutaml::Lml::Document)
      expect(doc.title).to eq("Test")
    end

    it "creates a class with name" do
      klass = builder.build(:class, { name: "MyClass" })
      expect(klass).to be_a(Lutaml::Lml::UmlClass)
      expect(klass.name).to eq("MyClass")
    end

    it "creates an enum" do
      enum = builder.build(:enum, { name: "Color" })
      expect(enum).to be_a(Lutaml::Lml::Enum)
      expect(enum.name).to eq("Color")
    end

    it "creates an attribute with type" do
      attr = builder.build(:attribute, { name: "id", type: "String" })
      expect(attr).to be_a(Lutaml::Lml::TopElementAttribute)
      expect(attr.name).to eq("id")
      expect(attr.type).to eq("String")
    end

    it "creates a cardinality" do
      card = builder.build(:cardinality, { min: "0", max: "*" })
      expect(card).to be_a(Lutaml::Lml::Cardinality)
      expect(card.min).to eq("0")
      expect(card.max).to eq("*")
    end
  end

  describe "#build with members" do
    it "builds nested members from members key" do
      hash = {
        title: "Doc",
        members: [
          { classes: { name: "ClassA" } },
          { enums: { name: "EnumA" } },
        ],
      }
      doc = builder.build(:document, hash)
      expect(doc.title).to eq("Doc")
      expect(doc.classes.length).to eq(1)
      expect(doc.enums.length).to eq(1)
    end

    it "appends to existing collections" do
      doc = builder.build(:document, {
                            title: "First",
                            members: [{ classes: { name: "ClassA" } }],
                          })
      expect(doc.classes.length).to eq(1)
      expect(doc.classes.first.name).to eq("ClassA")
    end
  end

  describe "with the default registry" do
    it "creates LML-specific models" do
      doc = builder.build(:document, {})
      expect(doc).to be_a(Lutaml::Lml::Document)
    end

    it "creates LML UmlClass with parent_class" do
      klass = builder.build(:class, { name: "Child", parent_class: "Parent" })
      expect(klass).to be_a(Lutaml::Lml::UmlClass)
      expect(klass.parent_class).to eq("Parent")
    end
  end

  describe "registry" do
    it "maps document to LML Document" do
      expect(registry[:document]).to eq(Lutaml::Lml::Document)
    end

    it "maps class to LML UmlClass" do
      expect(registry[:class]).to eq(Lutaml::Lml::UmlClass)
    end

    it "maps all factory types" do
      expect(registry.keys).to include(
        :document, :class, :enum, :data_type, :attribute,
        :association, :operation, :constraint, :value, :cardinality,
        :diagram, :view_import, :view_filter
      )
    end
  end
end
