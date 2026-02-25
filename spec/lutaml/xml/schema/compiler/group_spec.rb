require "spec_helper"

RSpec.describe Lutaml::Model::Schema::XmlCompiler::Group do
  let(:group) { described_class.new("GroupName", nil) }
  let(:dummy_class) do
    Class.new do
      def to_attributes(indent); end
      def to_xml_mapping(indent); end
      def required_files; end
    end
  end

  describe "#initialize" do
    it "sets name and ref" do
      g = described_class.new("foo", "bar")
      expect(g.name).to eq("foo")
      expect(g.ref).to eq("bar")
    end
  end

  describe "#to_xml_mapping" do
    it "returns import_model_mappings if ref is present" do
      group.ref = "foo:Bar"
      group.name = nil
      expect(group.to_xml_mapping("  ")).to include("import_model_mappings :bar")
    end

    it "delegates to instance if ref is not present" do
      instance = instance_double(dummy_class,
                                 to_xml_mapping: "  map_element :foo, to: :foo\n")
      group.instance = instance
      group.ref = nil
      expect(group.to_xml_mapping("  ")).to include("map_element :foo, to: :foo")
    end
  end

  describe "#to_class" do
    it "renders the group template" do
      group.name = "GroupName"
      group.instance = instance_double(dummy_class,
                                       to_attributes: "  attribute :foo, :string\n", to_xml_mapping: "  map_element :foo, to: :foo\n", required_files: [])
      expect(group.to_class).to include("class GroupName")
      expect(group.to_class).to include("attribute :foo, :string")
      expect(group.to_class).to include("map_element :foo, to: :foo")
    end
  end

  describe "#required_files" do
    it "returns require_relative if name is blank and ref is present" do
      group.name = nil
      group.ref = "foo:Bar"
      expect(group.required_files).to include("require_relative \"bar\"")
    end

    it "delegates to instance if name is present" do
      instance = instance_double(dummy_class, required_files: "require 'foo'")
      group.instance = instance
      group.name = "GroupName"
      group.ref = nil
      expect(group.required_files).to eq("require 'foo'")
    end
  end

  describe "#to_attributes" do
    it "returns import_model_attributes if ref is present" do
      group.ref = "foo:Bar"
      group.name = nil
      expect(group.to_attributes("  ")).to include("import_model_attributes :bar")
    end

    it "delegates to instance if ref is not present" do
      instance = instance_double(dummy_class,
                                 to_attributes: "  attribute :foo, :string\n")
      group.instance = instance
      group.ref = nil
      expect(group.to_attributes("  ")).to include("attribute :foo, :string")
    end
  end

  describe "#base_name" do
    it "returns last part of name or ref" do
      group.name = "foo:Bar"
      expect(group.base_name).to eq("Bar")
      group.name = nil
      group.ref = "foo:Baz"
      expect(group.base_name).to eq("Baz")
    end
  end
end
