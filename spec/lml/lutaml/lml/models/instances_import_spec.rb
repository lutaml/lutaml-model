# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::InstancesImport do
  it "has format_type and file attributes" do
    imp = described_class.new(format_type: "xml", file: "data/products.xml")
    expect(imp.format_type).to eq("xml")
    expect(imp.file).to eq("data/products.xml")
  end

  it "holds attributes as TopElementAttribute collection" do
    attrs = [
      Lutaml::Lml::TopElementAttribute.new(name: "map_to", value: "Product"),
      Lutaml::Lml::TopElementAttribute.new(name: "id", value: "product_id"),
    ]
    imp = described_class.new(format_type: "csv", attributes: attrs)
    expect(imp.attributes.length).to eq(2)
    expect(imp.attributes[0].name).to eq("map_to")
    expect(imp.attributes[1].name).to eq("id")
  end

  it "defaults to empty attributes" do
    imp = described_class.new(format_type: "csv")
    expect(imp.attributes).to eq([])
  end
end
