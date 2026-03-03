# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Lutaml::Xml::Schema::Xsd::FileValidationResult do
  describe "#initialize" do
    it "creates a valid result" do
      result = described_class.new(
        file: "schema.xsd",
        valid: true,
      )

      expect(result.file).to eq("schema.xsd")
      expect(result.success?).to be true
      expect(result.failure?).to be false
      expect(result.error).to be_nil
      expect(result.detected_version).to be_nil
    end

    it "creates an invalid result with error" do
      result = described_class.new(
        file: "bad.xsd",
        valid: false,
        error: "Invalid XML syntax",
      )

      expect(result.file).to eq("bad.xsd")
      expect(result.success?).to be false
      expect(result.failure?).to be true
      expect(result.error).to eq("Invalid XML syntax")
    end

    it "includes detected version when provided" do
      result = described_class.new(
        file: "schema.xsd",
        valid: true,
        detected_version: "1.1",
      )

      expect(result.detected_version).to eq("1.1")
    end
  end

  describe "#success?" do
    it "returns true for valid file" do
      result = described_class.new(file: "test.xsd", valid: true)
      expect(result.success?).to be true
    end

    it "returns false for invalid file" do
      result = described_class.new(
        file: "test.xsd",
        valid: false,
        error: "Error",
      )
      expect(result.success?).to be false
    end
  end

  describe "#failure?" do
    it "returns false for valid file" do
      result = described_class.new(file: "test.xsd", valid: true)
      expect(result.failure?).to be false
    end

    it "returns true for invalid file" do
      result = described_class.new(
        file: "test.xsd",
        valid: false,
        error: "Error",
      )
      expect(result.failure?).to be true
    end
  end

  describe "#to_h" do
    it "converts valid result to hash" do
      result = described_class.new(
        file: "schema.xsd",
        valid: true,
        detected_version: "1.0",
      )

      hash = result.to_h
      expect(hash[:file]).to eq("schema.xsd")
      expect(hash[:valid]).to be true
      expect(hash[:detected_version]).to eq("1.0")
      expect(hash).not_to have_key(:error)
    end

    it "converts invalid result to hash" do
      result = described_class.new(
        file: "bad.xsd",
        valid: false,
        error: "Invalid XML",
      )

      hash = result.to_h
      expect(hash[:file]).to eq("bad.xsd")
      expect(hash[:valid]).to be false
      expect(hash[:error]).to eq("Invalid XML")
      expect(hash).not_to have_key(:detected_version)
    end

    it "omits nil values" do
      result = described_class.new(file: "test.xsd", valid: true)
      hash = result.to_h

      expect(hash).to eq({
                           file: "test.xsd",
                           valid: true,
                         })
    end
  end

  describe "#to_s" do
    it "formats valid result" do
      result = described_class.new(file: "schema.xsd", valid: true)
      expect(result.to_s).to eq("schema.xsd: VALID")
    end

    it "formats invalid result with error" do
      result = described_class.new(
        file: "bad.xsd",
        valid: false,
        error: "Not a valid XSD",
      )
      expect(result.to_s).to eq("bad.xsd: INVALID - Not a valid XSD")
    end
  end
end
