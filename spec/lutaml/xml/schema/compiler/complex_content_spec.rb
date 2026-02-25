require "spec_helper"

RSpec.describe Lutaml::Model::Schema::XmlCompiler::ComplexContent do
  let(:dummy_class) do
    Class.new do
      def to_attributes(indent); end
      def to_xml_mapping(indent); end
      def required_files; end
    end
  end
  let(:restriction) do
    instance_double(dummy_class, to_attributes: "attr", to_xml_mapping: "xml",
                                 required_files: "files")
  end
  let(:complex_content) { described_class.new(restriction) }

  describe "#initialize" do
    it "sets restriction" do
      expect(complex_content.restriction).to eq(restriction)
    end
  end

  describe "#to_attributes" do
    it "delegates to restriction" do
      expect(complex_content.to_attributes("  ")).to eq("attr")
    end
  end

  describe "#to_xml_mapping" do
    it "delegates to restriction" do
      expect(complex_content.to_xml_mapping("  ")).to eq("xml")
    end
  end

  describe "#required_files" do
    it "delegates to restriction" do
      expect(complex_content.required_files).to eq("files")
    end
  end
end
