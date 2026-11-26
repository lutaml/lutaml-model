# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"

RSpec.describe Lutaml::Lml::ViewResolver do
  let(:resolver) { described_class.new }

  describe "#resolve" do
    it "returns all entities when no filters" do
      klass1 = Lutaml::Lml::UmlClass.new(name: "Foo")
      klass2 = Lutaml::Lml::UmlClass.new(name: "Bar")
      doc = Lutaml::Lml::Document.new
      entities = { "Foo" => klass1, "Bar" => klass2 }
      associations = []

      visible, filtered_assoc = resolver.resolve(doc, entities, associations)
      expect(visible.map(&:name)).to eq(["Foo", "Bar"])
    end

    it "filters to show_list only" do
      foo = Lutaml::Lml::UmlClass.new(name: "Foo")
      bar = Lutaml::Lml::UmlClass.new(name: "Bar")
      baz = Lutaml::Lml::UmlClass.new(name: "Baz")
      doc = Lutaml::Lml::Document.new(
        show_filter: Lutaml::Lml::ViewFilter.new(entity_names: ["Foo", "Bar"])
      )
      entities = { "Foo" => foo, "Bar" => bar, "Baz" => baz }

      visible, = resolver.resolve(doc, entities, [])
      expect(visible.map(&:name)).to eq(["Foo", "Bar"])
    end

    it "filters out hide_list entities" do
      foo = Lutaml::Lml::UmlClass.new(name: "Foo")
      bar = Lutaml::Lml::UmlClass.new(name: "Bar")
      baz = Lutaml::Lml::UmlClass.new(name: "Baz")
      doc = Lutaml::Lml::Document.new(
        hide_filter: Lutaml::Lml::ViewFilter.new(entity_names: ["Baz"])
      )
      entities = { "Foo" => foo, "Bar" => bar, "Baz" => baz }

      visible, = resolver.resolve(doc, entities, [])
      expect(visible.map(&:name)).to eq(["Foo", "Bar"])
    end

    it "combines show and hide filters" do
      foo = Lutaml::Lml::UmlClass.new(name: "Foo")
      bar = Lutaml::Lml::UmlClass.new(name: "Bar")
      baz = Lutaml::Lml::UmlClass.new(name: "Baz")
      doc = Lutaml::Lml::Document.new(
        show_filter: Lutaml::Lml::ViewFilter.new(entity_names: ["Foo", "Bar", "Baz"]),
        hide_filter: Lutaml::Lml::ViewFilter.new(entity_names: ["Baz"])
      )
      entities = { "Foo" => foo, "Bar" => bar, "Baz" => baz }

      visible, = resolver.resolve(doc, entities, [])
      expect(visible.map(&:name)).to eq(["Foo", "Bar"])
    end

    it "filters associations to only those with both ends visible" do
      foo = Lutaml::Lml::UmlClass.new(name: "Foo")
      bar = Lutaml::Lml::UmlClass.new(name: "Bar")
      baz = Lutaml::Lml::UmlClass.new(name: "Baz")
      assoc1 = Lutaml::Lml::Association.new(owner_end: "Foo", member_end: "Bar")
      assoc2 = Lutaml::Lml::Association.new(owner_end: "Foo", member_end: "Baz")
      doc = Lutaml::Lml::Document.new(
        hide_filter: Lutaml::Lml::ViewFilter.new(entity_names: ["Baz"])
      )
      entities = { "Foo" => foo, "Bar" => bar, "Baz" => baz }

      _, filtered_assoc = resolver.resolve(doc, entities, [assoc1, assoc2])
      expect(filtered_assoc.length).to eq(1)
      expect(filtered_assoc.first.owner_end).to eq("Foo")
      expect(filtered_assoc.first.member_end).to eq("Bar")
    end
  end
end
