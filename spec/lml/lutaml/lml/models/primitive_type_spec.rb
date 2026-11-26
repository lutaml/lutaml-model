# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::PrimitiveType do
  describe "attribute definitions" do
    it "has name attribute" do
      pt = described_class.new(name: "Integer")
      expect(pt.name).to eq("Integer")
    end

    it "has default keyword" do
      pt = described_class.new
      expect(pt.keyword).to eq("primitive")
    end

    it "has default visibility" do
      pt = described_class.new
      expect(pt.visibility).to eq("public")
    end

    it "has default is_abstract" do
      pt = described_class.new
      expect(pt.is_abstract).to eq(false)
    end
  end

  describe ".entity_type" do
    it "returns :primitives" do
      expect(described_class.entity_type).to eq(:primitives)
    end
  end
end
