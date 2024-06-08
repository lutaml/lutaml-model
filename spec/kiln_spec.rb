# spec/kiln_spec.rb
require "spec_helper"
require_relative "fixtures/kiln"

RSpec.describe Kiln do
  let(:attributes) {
    {
      brand: "Skutt",
      capacity: 7.5,
      firing: "cone 10",
    }
  }
  let(:model) { Kiln.new(attributes) }

  it "serializes to JSON with default mappings" do
    expected_json = {
      brand: "Skutt",
      capacity: 7.5,
      firing: "cone 10",
    }.to_json

    expect(model.to_json).to eq(expected_json)
  end

  it "deserializes from JSON with default mappings" do
    json = attributes.to_json
    kiln = Kiln.from_json(json)
    expect(kiln.brand).to eq("Skutt")
    expect(kiln.capacity).to eq(7.5)
    expect(kiln.firing).to eq("cone 10")
  end

  it "serializes to XML with default mappings" do
    expected_xml = Nokogiri::XML::Builder.new do |xml|
      xml.kiln(brand: "Skutt") {
        xml.capacity "7.5"
        xml.firing "cone 10"
      }
    end.to_xml

    expect(Nokogiri::XML(model.to_xml).to_s).to eq(Nokogiri::XML(expected_xml).to_s)
  end

  it "deserializes from XML with default mappings" do
    xml = Nokogiri::XML::Builder.new do |xml|
      xml.kiln(brand: "Skutt") {
        xml.capacity "7.5"
        xml.firing "cone 10"
      }
    end.to_xml

    kiln = Kiln.from_xml(xml)
    expect(kiln.brand).to eq("Skutt")
    expect(kiln.capacity).to eq(7.5)
    expect(kiln.firing).to eq("cone 10")
  end

  it "serializes to YAML with default mappings" do
    expected_yaml = <<-YAML
---
brand: Skutt
capacity: 7.5
firing: cone 10
    YAML

    expect(model.to_yaml.strip).to eq(expected_yaml.strip)
  end

  it "deserializes from YAML with default mappings" do
    yaml = <<-YAML
---
brand: Skutt
capacity: 7.5
firing: cone 10
    YAML

    kiln = Kiln.from_yaml(yaml)
    expect(kiln.brand).to eq("Skutt")
    expect(kiln.capacity).to eq(7.5)
    expect(kiln.firing).to eq("cone 10")
  end

  it "serializes to TOML with default mappings" do
    expected_toml = <<-TOML
brand = "Skutt"
capacity = 7.5
firing = "cone 10"
    TOML

    expect(model.to_toml.strip).to eq(expected_toml.strip)
  end

  it "deserializes from TOML with default mappings" do
    toml = <<-TOML
brand = "Skutt"
capacity = 7.5
firing = "cone 10"
    TOML

    kiln = Kiln.from_toml(toml)
    expect(kiln.brand).to eq("Skutt")
    expect(kiln.capacity).to eq(7.5)
    expect(kiln.firing).to eq("cone 10")
  end
end
