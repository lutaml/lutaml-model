# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"

RSpec.describe Lutaml::Lml::AssociationLabelResolver do
  let(:resolver) { described_class.new }

  describe "#enrich" do
    it "populates owner_end_attribute_name from matching class attribute type" do
      attr = Lutaml::Lml::TopElementAttribute.new(
        name: "docIdentifier", type: "IsoDocumentId"
      )
      klass = Lutaml::Lml::UmlClass.new(
        name: "IsoBibliographicItem", attributes: [attr]
      )
      assoc = Lutaml::Lml::Association.new(
        owner_end: "IsoBibliographicItem", member_end: "IsoDocumentId"
      )
      doc = Lutaml::Lml::Document.new(
        classes: [klass], associations: [assoc]
      )

      resolver.enrich(doc)

      expect(assoc.owner_end_attribute_name).to eq("docIdentifier")
    end

    it "populates owner_end_cardinality when attribute has cardinality" do
      card = Lutaml::Lml::Cardinality.new(min: "0", max: "1")
      attr = Lutaml::Lml::TopElementAttribute.new(
        name: "type", type: "IsoDocumentType", cardinality: card
      )
      klass = Lutaml::Lml::UmlClass.new(
        name: "IsoBibliographicItem", attributes: [attr]
      )
      assoc = Lutaml::Lml::Association.new(
        owner_end: "IsoBibliographicItem", member_end: "IsoDocumentType"
      )
      doc = Lutaml::Lml::Document.new(
        classes: [klass], associations: [assoc]
      )

      resolver.enrich(doc)

      expect(assoc.owner_end_attribute_name).to eq("type")
      expect(assoc.owner_end_cardinality.min).to eq("0")
      expect(assoc.owner_end_cardinality.max).to eq("1")
    end

    it "does not overwrite existing owner_end_attribute_name" do
      attr = Lutaml::Lml::TopElementAttribute.new(
        name: "override_me", type: "IsoDocumentId"
      )
      klass = Lutaml::Lml::UmlClass.new(
        name: "IsoBibliographicItem", attributes: [attr]
      )
      assoc = Lutaml::Lml::Association.new(
        owner_end: "IsoBibliographicItem", member_end: "IsoDocumentId",
        owner_end_attribute_name: "explicit_name"
      )
      doc = Lutaml::Lml::Document.new(
        classes: [klass], associations: [assoc]
      )

      resolver.enrich(doc)

      expect(assoc.owner_end_attribute_name).to eq("explicit_name")
    end

    it "populates member_end_attribute_name from matching attribute on member class" do
      attr = Lutaml::Lml::TopElementAttribute.new(
        name: "bibItem", type: "IsoBibliographicItem"
      )
      member_class = Lutaml::Lml::UmlClass.new(
        name: "IsoDocumentId", attributes: [attr]
      )
      assoc = Lutaml::Lml::Association.new(
        owner_end: "IsoBibliographicItem", member_end: "IsoDocumentId"
      )
      doc = Lutaml::Lml::Document.new(
        classes: [member_class], associations: [assoc]
      )

      resolver.enrich(doc)

      expect(assoc.member_end_attribute_name).to eq("bibItem")
    end

    it "skips association when owner class is not in document" do
      assoc = Lutaml::Lml::Association.new(
        owner_end: "MissingClass", member_end: "IsoDocumentId"
      )
      doc = Lutaml::Lml::Document.new(classes: [], associations: [assoc])

      resolver.enrich(doc)

      expect(assoc.owner_end_attribute_name).to be_nil
    end

    it "skips when no attribute type matches member_end" do
      attr = Lutaml::Lml::TopElementAttribute.new(
        name: "name", type: "String"
      )
      klass = Lutaml::Lml::UmlClass.new(
        name: "Foo", attributes: [attr]
      )
      assoc = Lutaml::Lml::Association.new(
        owner_end: "Foo", member_end: "Bar"
      )
      doc = Lutaml::Lml::Document.new(
        classes: [klass], associations: [assoc]
      )

      resolver.enrich(doc)

      expect(assoc.owner_end_attribute_name).to be_nil
    end

    it "searches enums and data_types in addition to classes" do
      attr = Lutaml::Lml::TopElementAttribute.new(
        name: "status", type: "Status"
      )
      enum = Lutaml::Lml::Enum.new(
        name: "MyClass", attributes: [attr]
      )
      assoc = Lutaml::Lml::Association.new(
        owner_end: "MyClass", member_end: "Status"
      )
      doc = Lutaml::Lml::Document.new(
        enums: [enum], associations: [assoc]
      )

      resolver.enrich(doc)

      expect(assoc.owner_end_attribute_name).to eq("status")
    end
  end
end
