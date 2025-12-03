require "spec_helper"

RSpec.describe Lutaml::Model::Schema::XmlCompiler::Sequence do
  let(:sequence) { described_class.new }
  let(:dummy_class) do
    Class.new do
      def to_attributes(indent); end
      def to_xml_mapping(indent); end
      def required_files; end
    end
  end

  describe "#initialize" do
    it "starts with empty instances" do
      expect(sequence.instances).to eq([])
    end
  end

  describe "#<<" do
    it "adds instances to the list" do
      instance = instance_double(dummy_class,
                                 to_attributes: "  attribute :foo, :string\n", to_xml_mapping: "    map_element :foo, to: :foo\n", required_files: "require 'foo'")
      expect { sequence << instance }.to change {
        sequence.instances.size
      }.by(1)
      expect(sequence.instances).to include(instance)
    end

    it "ignores nil instances" do
      expect { sequence << nil }.not_to(change { sequence.instances.size })
    end
  end

  describe "#to_attributes" do
    it "returns joined attributes from instances" do
      instance = instance_double(dummy_class,
                                 to_attributes: "  attribute :foo, :string\n")
      sequence << instance
      expect(sequence.to_attributes("  ")).to include("attribute :foo, :string")
    end
  end

  describe "#to_xml_mapping" do
    it "returns empty string if no content" do
      expect(sequence.to_xml_mapping("  ")).to eq("")
    end

    it "returns xml mapping block if content exists" do
      instance = instance_double(dummy_class,
                                 to_xml_mapping: "    map_element :foo, to: :foo\n")
      sequence << instance
      expect(sequence.to_xml_mapping("  ")).to include("sequence do")
      expect(sequence.to_xml_mapping("  ")).to include("map_element :foo, to: :foo")
    end
  end

  describe "#required_files" do
    it "collects required_files from all instances" do
      instance = instance_double(dummy_class, required_files: "require 'foo'")
      sequence << instance
      expect(sequence.required_files).to include("require 'foo'")
    end
  end
end
