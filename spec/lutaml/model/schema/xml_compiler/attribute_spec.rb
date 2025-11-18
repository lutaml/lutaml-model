require "spec_helper"

RSpec.describe Lutaml::Model::Schema::XmlCompiler::Attribute do
  let(:attribute) { described_class.new(name: "foo", ref: "bar:Ref") }

  describe "#initialize" do
    it "sets name and ref" do
      a = described_class.new(name: "foo", ref: "bar")
      expect(a.name).to eq("foo")
      expect(a.ref).to eq("bar")
    end
  end

  describe "#to_attributes" do
    it "returns attribute line if not skippable" do
      allow(attribute).to receive_messages(skippable?: false,
                                           resolved_name: "foo", resolved_type: "string")
      expect(attribute.to_attributes("  ")).to include("attribute :foo, :string")
    end

    it "returns nil if skippable" do
      allow(attribute).to receive(:skippable?).and_return(true)
      expect(attribute.to_attributes("  ")).to be_nil
    end
  end

  describe "#to_xml_mapping" do
    it "returns map_attribute line if not skippable" do
      allow(attribute).to receive_messages(skippable?: false,
                                           resolved_name: "foo")
      expect(attribute.to_xml_mapping("  ")).to include("map_attribute :foo, to: :foo")
    end

    it "returns nil if skippable" do
      allow(attribute).to receive(:skippable?).and_return(true)
      expect(attribute.to_xml_mapping("  ")).to be_nil
    end
  end

  describe "#required_files" do
    it "returns require 'bigdecimal' for decimal type" do
      allow(attribute).to receive_messages(skippable?: false,
                                           resolved_type: "decimal")
      expect(attribute.required_files).to eq("require \"bigdecimal\"")
    end

    it "returns require_relative for non-skippable type" do
      allow(attribute).to receive_messages(skippable?: false,
                                           resolved_type: "foo")
      allow(Lutaml::Model::Schema::XmlCompiler::SimpleType).to receive(:skippable?).and_return(false)
      expect(attribute.required_files).to eq("require_relative \"foo\"")
    end

    it "returns nil for skippable type" do
      allow(attribute).to receive(:skippable?).and_return(true)
      expect(attribute.required_files).to be_nil
    end
  end

  describe "private methods" do
    it "last_of_split returns last part after colon" do
      expect(attribute.send(:last_of_split, "foo:Bar")).to eq("Bar")
      expect(attribute.send(:last_of_split, "Bar")).to eq("Bar")
      expect(attribute.send(:last_of_split, nil)).to be_nil
    end
  end
end
