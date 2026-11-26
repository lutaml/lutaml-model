# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::InstanceCollection do
  describe "default attributes" do
    it "has empty instances by default" do
      ic = described_class.new
      expect(ic.instances).to eq([])
    end

    it "has empty imports by default" do
      ic = described_class.new
      expect(ic.imports).to eq([])
    end

    it "has empty exports by default" do
      ic = described_class.new
      expect(ic.exports).to eq([])
    end

    it "has empty collections by default" do
      ic = described_class.new
      expect(ic.collections).to eq([])
    end
  end

  describe "with populated data" do
    let(:ic) do
      inst = Lutaml::Lml::Instance.new(type: "Product")
      imp = Lutaml::Lml::InstancesImport.new(format_type: "xml", file: "data.xml")
      exp = Lutaml::Lml::InstancesExport.new(format_type: "json")
      coll = Lutaml::Lml::Collection.new(name: "all_products")
      described_class.new(
        instances: [inst],
        imports: [imp],
        exports: [exp],
        collections: coll
      )
    end

    it "holds instances" do
      expect(ic.instances.length).to eq(1)
      expect(ic.instances.first.type).to eq("Product")
    end

    it "holds imports" do
      expect(ic.imports.length).to eq(1)
      expect(ic.imports.first.format_type).to eq("xml")
    end

    it "holds exports" do
      expect(ic.exports.length).to eq(1)
      expect(ic.exports.first.format_type).to eq("json")
    end

    it "holds collection" do
      expect(ic.collections.first.name).to eq("all_products")
    end
  end
end
