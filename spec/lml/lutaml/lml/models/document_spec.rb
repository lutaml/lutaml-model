# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::Document do
  describe "inheritance" do
    it "inherits from Lutaml::Model::Serializable" do
      expect(described_class).to be < Lutaml::Model::Serializable
    end
  end

  describe "attributes" do
    it "has instance attribute" do
      doc = described_class.new
      expect(doc.instance).to be_nil
    end

    it "has requires collection defaulting to empty" do
      doc = described_class.new
      expect(doc.requires).to eq([])
    end

    it "has instances attribute" do
      doc = described_class.new
      expect(doc.instances).to be_nil
    end

    it "defaults view_imports to a fresh empty array per instance" do
      first = described_class.new
      second = described_class.new
      expect(first.view_imports).to eq([])
      expect(first.view_imports).not_to equal(second.view_imports)
    end

    it "defaults comments and groups to empty arrays" do
      doc = described_class.new
      expect(doc.comments).to eq([])
      expect(doc.groups).to eq([])
    end
  end

  describe "setting attributes" do
    it "accepts requires list" do
      doc = described_class.new
      doc.requires = ["file1.lml", "file2.lml"]
      expect(doc.requires).to eq(["file1.lml", "file2.lml"])
    end

    it "accepts an instance" do
      inst = Lutaml::Lml::Instance.new(type: "MyType")
      doc = described_class.new
      doc.instance = inst
      expect(doc.instance.type).to eq("MyType")
    end

    it "accepts an InstanceCollection" do
      collection = Lutaml::Lml::InstanceCollection.new
      doc = described_class.new
      doc.instances = collection
      expect(doc.instances).to eq(collection)
    end
  end
end
