require "spec_helper"

RSpec.describe Lutaml::Model::Schema::XmlCompiler::Choice do
  let(:choice) { described_class.new }
  let(:dummy_class) do
    Class.new do
      def to_attributes(indent); end
      def to_xml_mapping(indent); end
      def required_files; end
    end
  end

  describe "#initialize" do
    it "starts with empty instances" do
      expect(choice.instances).to eq([])
    end
  end

  describe "#<<" do
    it "adds instances to the list" do
      instance = instance_double(dummy_class)
      expect { choice << instance }.to change { choice.instances.size }.by(1)
      expect(choice.instances).to include(instance)
    end

    it "ignores nil instances" do
      expect { choice << nil }.not_to(change { choice.instances.size })
    end
  end

  describe "#to_attributes" do
    it "renders the choice block with min/max options" do
      instance = instance_double(dummy_class, to_attributes: "    attribute :foo, :string\n")
      choice << instance
      choice.min_occurs = 1
      choice.max_occurs = 2
      expect(choice.to_attributes("  ")).to include("choice(")
      expect(choice.to_attributes("  ")).to include("attribute :foo, :string")
    end
  end

  describe "#to_xml_mapping" do
    it "returns joined xml mappings from instances" do
      instance = instance_double(dummy_class, to_xml_mapping: "    map_element :foo, to: :foo\n")
      choice << instance
      expect(choice.to_xml_mapping("  ")).to include("map_element :foo, to: :foo")
    end
  end

  describe "#required_files" do
    it "collects required_files from all instances" do
      instance = instance_double(dummy_class, required_files: "require 'foo'")
      choice << instance
      expect(choice.required_files).to include("require 'foo'")
    end
  end

  describe "private methods" do
    it "min_option returns correct min" do
      choice.min_occurs = 3
      expect(choice.send(:min_option)).to include("min: 3")
    end

    it "max_option returns correct max" do
      choice.max_occurs = "unbounded"
      expect(choice.send(:max_option)).to include("Float::INFINITY")
      choice.max_occurs = 5
      expect(choice.send(:max_option)).to include("max: 5")
    end
  end
end
