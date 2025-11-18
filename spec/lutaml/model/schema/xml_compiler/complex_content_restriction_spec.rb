require "spec_helper"

RSpec.describe Lutaml::Model::Schema::XmlCompiler::ComplexContentRestriction do
  let(:restriction) { described_class.new(base: "Base", instances: []) }
  let(:dummy_class) do
    Class.new do
      def to_attributes(indent); end
      def to_xml_mapping(indent); end
      def required_files; end
    end
  end

  describe "#initialize" do
    it "sets base and instances" do
      r = described_class.new(base: "foo", instances: [1, 2])
      expect(r.base).to eq("foo")
      expect(r.instances).to eq([1, 2])
    end
  end

  describe "#<<" do
    it "adds instances to the list" do
      expect { restriction << 1 }.to change { restriction.instances.size }.by(1)
      expect(restriction.instances).to include(1)
    end

    it "ignores nil instances" do
      expect { restriction << nil }.not_to(change do
        restriction.instances.size
      end)
    end
  end

  describe "#to_attributes" do
    it "returns attributes from all instances" do
      instance = instance_double(dummy_class, to_attributes: "attr")
      restriction.instances = [instance]
      expect(restriction.to_attributes("  ")).to include("attr")
    end
  end

  describe "#to_xml_mapping" do
    it "returns xml mappings from all instances" do
      instance = instance_double(dummy_class, to_xml_mapping: "xml")
      restriction.instances = [instance]
      expect(restriction.to_xml_mapping("  ")).to include("xml")
    end
  end

  describe "#required_files" do
    it "collects required_files from all instances" do
      instance = instance_double(dummy_class, required_files: "files")
      restriction.instances = [instance]
      expect(restriction.required_files).to include("files")
    end
  end
end
