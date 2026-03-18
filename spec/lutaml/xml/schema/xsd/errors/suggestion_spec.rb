# frozen_string_literal: true

require_relative "../spec_helper"
require "lutaml/xml/schema/xsd/errors/suggestion"

RSpec.describe Lutaml::Xml::Schema::Xsd::Errors::Suggestion do
  describe "#initialize" do
    it "creates suggestion with required attributes" do
      suggestion = described_class.new(
        text: "CodeType",
        similarity: 0.85,
      )

      expect(suggestion.text).to eq("CodeType")
      expect(suggestion.similarity).to eq(0.85)
    end

    it "generates default explanation" do
      suggestion = described_class.new(text: "CodeType")

      expect(suggestion.explanation).to eq("Did you mean 'CodeType'?")
    end

    it "accepts custom explanation" do
      suggestion = described_class.new(
        text: "CodeType",
        explanation: "Try CodeType instead",
      )

      expect(suggestion.explanation).to eq("Try CodeType instead")
    end

    it "defaults similarity to 1.0" do
      suggestion = described_class.new(text: "CodeType")

      expect(suggestion.similarity).to eq(1.0)
    end
  end

  describe "#similarity_percentage" do
    it "converts similarity to percentage" do
      suggestion = described_class.new(text: "Type", similarity: 0.857)

      expect(suggestion.similarity_percentage).to eq(86)
    end

    it "rounds to nearest integer" do
      suggestion = described_class.new(text: "Type", similarity: 0.855)

      expect(suggestion.similarity_percentage).to eq(86)
    end
  end

  describe "#to_h" do
    it "converts to hash" do
      suggestion = described_class.new(
        text: "CodeType",
        similarity: 0.85,
        explanation: "Similar type found",
      )

      hash = suggestion.to_h
      expect(hash[:text]).to eq("CodeType")
      expect(hash[:similarity]).to eq(0.85)
      expect(hash[:explanation]).to eq("Similar type found")
    end
  end

  describe "#<=>" do
    it "orders by similarity descending" do
      high = described_class.new(text: "A", similarity: 0.9)
      low = described_class.new(text: "B", similarity: 0.5)

      expect([low, high].sort).to eq([high, low])
    end
  end
end
