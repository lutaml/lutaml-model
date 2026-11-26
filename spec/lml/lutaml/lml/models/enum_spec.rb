# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::Enum do
  describe "attribute definitions" do
    it "has name attribute" do
      enum = described_class.new(name: "Color")
      expect(enum.name).to eq("Color")
    end

    it "has default keyword" do
      enum = described_class.new
      expect(enum.keyword).to eq("enumeration")
    end

    it "has default visibility" do
      enum = described_class.new
      expect(enum.visibility).to eq("public")
    end

    it "has default is_abstract" do
      enum = described_class.new
      expect(enum.is_abstract).to eq(false)
    end

    it "has collection attributes with defaults" do
      enum = described_class.new
      expect(enum.attributes).to eq([])
      expect(enum.operations).to eq([])
      expect(enum.values).to eq([])
      expect(enum.stereotype).to eq([])
    end
  end

  describe ".entity_type" do
    it "returns :enums" do
      expect(described_class.entity_type).to eq(:enums)
    end
  end
end
