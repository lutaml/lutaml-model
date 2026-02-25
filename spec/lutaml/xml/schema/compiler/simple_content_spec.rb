require "spec_helper"

RSpec.describe Lutaml::Model::Schema::XmlCompiler::SimpleContent do
  let(:simple_content) { described_class.new }
  let(:dummy_class) do
    Class.new do
      def to_attributes(indent); end
      def to_xml_mapping(indent); end
      def required_files; end
    end
  end

  describe "#initialize" do
    it "starts with empty instances and nil base_class" do
      expect(simple_content.instances).to eq([])
      expect(simple_content.base_class).to be_nil
    end
  end

  describe "#<<" do
    it "adds instances to the list" do
      instance = instance_double(dummy_class, to_attributes: "attr",
                                              to_xml_mapping: "xml", required_files: "files")
      expect { simple_content << instance }.to change {
        simple_content.instances.size
      }.by(1)
      expect(simple_content.instances).to include(instance)
    end

    it "ignores nil instances" do
      expect { simple_content << nil }.not_to(change do
        simple_content.instances.size
      end)
    end
  end

  describe "#to_attributes" do
    it "returns joined attributes from instances" do
      instance = instance_double(dummy_class, to_attributes: "attr")
      simple_content << instance
      expect(simple_content.to_attributes("  ")).to include("attr")
    end
  end

  describe "#to_xml_mapping" do
    it "returns joined xml mappings from instances" do
      instance = instance_double(dummy_class, to_xml_mapping: "xml")
      simple_content << instance
      expect(simple_content.to_xml_mapping("  ")).to include("xml")
    end
  end

  describe "#required_files" do
    it "collects required_files from all instances" do
      instance = instance_double(dummy_class, required_files: "files")
      simple_content << instance
      expect(simple_content.required_files).to include("files")
    end
  end
end
