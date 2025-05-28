require "spec_helper"

RSpec.describe Lutaml::Model::Schema::XmlCompiler::Restriction do
  let(:restriction) { described_class.new }

  describe "attribute accessors" do
    it "allows reading and writing all attributes" do
      restriction.min_inclusive = 1
      restriction.max_inclusive = 10
      restriction.min_exclusive = 2
      restriction.max_exclusive = 9
      restriction.enumerations = ["A", "B"]
      restriction.max_length = 5
      restriction.min_length = 1
      restriction.base_class = "foo:Bar"
      restriction.pattern = /abc/
      restriction.length = 3
      restriction.transform = "value.upcase"
      expect(restriction.min_inclusive).to eq(1)
      expect(restriction.max_inclusive).to eq(10)
      expect(restriction.enumerations).to eq(["A", "B"])
      expect(restriction.pattern).to eq(/abc/)
      expect(restriction.transform).to eq("value.upcase")
    end
  end

  describe "#to_method_body" do
    it "returns method body for all present attributes" do
      restriction.enumerations = ["A", "B"]
      restriction.min_inclusive = 1
      restriction.max_inclusive = 10
      restriction.pattern = /abc/
      restriction.transform = "value.upcase"
      body = restriction.to_method_body("  ")
      expect(body).to include("options[:values]")
      expect(body).to include("options[:min]")
      expect(body).to include("options[:max]")
      expect(body).to include("options[:pattern]")
      expect(body).to include("value = value.upcase")
    end

    it "returns empty string if no attributes are set" do
      expect(restriction.to_method_body("  ")).to eq("")
    end
  end

  describe "#required_files" do
    it "returns require 'bigdecimal' for decimal base_class" do
      restriction.base_class = "decimal"
      expect(restriction.required_files).to eq("require \"bigdecimal\"")
    end

    it "returns require_relative for non-skippable base_class" do
      restriction.base_class = "foo:Base"
      expect(restriction.required_files).to eq("require_relative \"base\"")
    end

    it "returns nil for skippable base_class" do
      restriction.base_class = "string"
      expect(restriction.required_files).to be_nil
    end
  end

  describe "private methods" do
    it "base_class_name returns last part as symbol" do
      restriction.base_class = "foo:Bar"
      expect(restriction.send(:base_class_name)).to eq(:Bar)
    end

    it "casted_enumerations returns super calls for each enumeration" do
      restriction.enumerations = ["A", "B"]
      expect(restriction.send(:casted_enumerations)).to include("super(\"A\")")
      expect(restriction.send(:casted_enumerations)).to include("super(\"B\")")
    end
  end
end
