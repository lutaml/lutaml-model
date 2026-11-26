# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"

RSpec.describe Lutaml::Lml::YamlParser do
  describe ".parse" do
    subject(:parse) { described_class.parse(yaml_path) }

    let(:yaml_path) do
      fixtures_path("uml/document.yml")
    end

    it "creates Lutaml::Lml::Document object" do
      expect(parse).to be_instance_of(Lutaml::Lml::Document)
    end

    it "parses document metadata", :aggregate_failures do
      expect(parse.name).to eq("TestDocument")
      expect(parse.title).to eq("Test Document Title")
    end

    it "contains nested groups", :aggregate_failures do
      groups = parse.groups
      expect(groups).to be_an(Array)
      expect(groups.size).to eq(2)
      expect(groups.first.id).to eq("TestGroup1")
      expect(groups.first.values).to eq(["TestGroup1a", "TestGroup1b"])
      expect(groups[1].id).to eq("TestGroup2")
      expect(groups[1].values).to eq(["TestGroup2a", "TestGroup2b", "TestGroup2c"])
      expect(groups[1].groups).to be_an(Array)
      expect(groups[1].groups.size).to eq(1)
      expect(groups[1].groups.first.id).to eq("TestSubGroup1")
    end

    it "parses enums with attributes and values" do
      enums = parse.enums
      expect(enums.size).to eq(1)
      expect(enums.first.name).to eq("TestEnum")
      expect(enums.first.attributes.first.name).to eq("TestAttribute")
      expect(enums.first.values.first.name).to eq("Test value")
    end

    it "parses nested packages" do
      packages = parse.packages
      expect(packages.size).to eq(1)
      expect(packages.first.name).to eq("Package")
      expect(packages.first.packages.first.name).to eq("NestedPackage")
      expect(packages.first.packages.first.packages.first.name).to eq("DeepNestedPackage")
    end
  end
end
