require "spec_helper"

RSpec.describe Lutaml::Model::Schema::XmlCompiler::Element do
  let(:element) { described_class.new(name: "foo", ref: "bar:Ref") }

  describe "#initialize" do
    it "sets name and ref" do
      e = described_class.new(name: "foo", ref: "bar")
      expect(e.name).to eq("foo")
      expect(e.ref).to eq("bar")
    end
  end

  describe "#to_attributes" do
    it "returns attribute line if not skippable and resolved_type present" do
      allow(element).to receive_messages(resolved_name: "foo", resolved_type: "string", skippable?: false)
      expect(element.to_attributes("  ")).to include("attribute :foo, :string")
    end

    it "returns nil if skippable" do
      allow(element).to receive(:skippable?).and_return(true)
      expect(element.to_attributes("  ")).to be_nil
    end
  end

  describe "#to_xml_mapping" do
    it "returns map_element line if not skippable and resolved_type present" do
      allow(element).to receive_messages(resolved_name: "foo", resolved_type: "string", skippable?: false)
      expect(element.to_xml_mapping("  ")).to include("map_element :foo, to: :foo")
    end

    it "returns nil if skippable" do
      allow(element).to receive(:skippable?).and_return(true)
      expect(element.to_xml_mapping("  ")).to be_nil
    end
  end

  describe "#required_files" do
    it "returns require 'bigdecimal' for decimal type" do
      allow(element).to receive_messages(resolved_name: "foo", resolved_type: "decimal", skippable?: false)
      expect(element.required_files).to eq("require \"bigdecimal\"")
    end

    it "returns require_relative for non-skippable type" do
      allow(Lutaml::Model::Schema::XmlCompiler::SimpleType).to receive(:skippable?).and_return(false)
      allow(element).to receive_messages(resolved_name: "foo", resolved_type: "foo")
      expect(element.required_files).to eq("require_relative \"foo\"")
    end

    it "returns nil for skippable type" do
      allow(element).to receive(:skippable?).and_return(true)
      expect(element.required_files).to be_nil
    end
  end

  describe "private methods" do
    it "last_of_split returns last part after colon" do
      expect(element.send(:last_of_split, "foo:Bar")).to eq("Bar")
      expect(element.send(:last_of_split, "Bar")).to eq("Bar")
      expect(element.send(:last_of_split, nil)).to be_nil
    end
  end
end
