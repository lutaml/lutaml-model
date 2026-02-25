require "spec_helper"

RSpec.describe Lutaml::Model::Schema::XmlCompiler::AttributeGroup do
  let(:attribute_group) { described_class.new(name: "foo", ref: nil) }
  let(:dummy_class) do
    Class.new do
      def to_attributes(indent); end
      def to_xml_mapping(indent); end
      def required_files; end
    end
  end

  describe "#initialize" do
    it "sets name, ref, and empty instances" do
      ag = described_class.new(name: "bar", ref: "baz")
      expect(ag.name).to eq("bar")
      expect(ag.ref).to eq("baz")
      expect(ag.instances).to eq([])
    end
  end

  describe "#<<" do
    it "adds instances to the list" do
      instance = instance_double(dummy_class, to_attributes: "attr",
                                              to_xml_mapping: "xml", required_files: "files")
      expect { attribute_group << instance }.to change {
        attribute_group.instances.size
      }.by(1)
      expect(attribute_group.instances).to include(instance)
    end

    it "ignores nil instances" do
      expect { attribute_group << nil }.not_to(change do
        attribute_group.instances.size
      end)
    end
  end

  describe "#to_attributes" do
    it "returns attributes from resolved_instances" do
      instance = instance_double(dummy_class, to_attributes: "attr")
      attribute_group.instances = [instance]
      expect(attribute_group.to_attributes("  ").join).to include("attr")
    end
  end

  describe "#to_xml_mapping" do
    it "returns xml mappings from resolved_instances" do
      instance = instance_double(dummy_class, to_xml_mapping: "xml")
      attribute_group.instances = [instance]
      expect(attribute_group.to_xml_mapping("  ").join).to include("xml")
    end
  end

  describe "#required_files" do
    it "collects required_files from resolved_instances" do
      instance = instance_double(dummy_class, required_files: "files")
      attribute_group.instances = [instance]
      expect(attribute_group.required_files.join).to include("files")
    end
  end

  describe "private methods" do
    it "resolved_instances returns @instances if ref is not present" do
      attribute_group.instances = [1, 2]
      attribute_group.ref = nil
      expect(attribute_group.send(:resolved_instances)).to eq([1, 2])
    end
  end
end
