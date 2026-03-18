# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Lutaml::Xml::Schema::Xsd::ValidationResult do
  let(:error1) do
    Lutaml::Xml::Schema::Xsd::ValidationError.create(
      field: :package,
      message: "Package path is required",
      constraint: "presence",
    )
  end

  let(:error2) do
    Lutaml::Xml::Schema::Xsd::ValidationError.create(
      field: :priority,
      message: "Must be non-negative",
      value: -1,
      constraint: ">= 0",
    )
  end

  describe ".success" do
    it "creates a valid result with no errors" do
      result = described_class.success

      expect(result).to be_valid
      expect(result.errors).to be_empty
    end
  end

  describe ".failure" do
    it "creates an invalid result with errors" do
      result = described_class.failure([error1, error2])

      expect(result).to be_invalid
      expect(result.errors.size).to eq(2)
      expect(result.errors).to include(error1, error2)
    end

    it "accepts empty error array" do
      result = described_class.failure([])

      expect(result).to be_invalid
      expect(result.errors).to be_empty
    end
  end

  describe "#valid?" do
    it "returns true for success result" do
      result = described_class.success
      expect(result.valid?).to be true
    end

    it "returns false for failure result" do
      result = described_class.failure([error1])
      expect(result.valid?).to be false
    end
  end

  describe "#invalid?" do
    it "returns false for success result" do
      result = described_class.success
      expect(result.invalid?).to be false
    end

    it "returns true for failure result" do
      result = described_class.failure([error1])
      expect(result.invalid?).to be true
    end
  end

  describe "#error_count" do
    it "returns 0 for success result" do
      result = described_class.success
      expect(result.error_count).to eq(0)
    end

    it "returns correct count for failure result" do
      result = described_class.failure([error1, error2])
      expect(result.error_count).to eq(2)
    end
  end

  describe "#error_messages" do
    it "returns empty array for success result" do
      result = described_class.success
      expect(result.error_messages).to be_empty
    end

    it "returns all error messages" do
      result = described_class.failure([error1, error2])

      expect(result.error_messages).to eq([
                                            "Package path is required",
                                            "Must be non-negative",
                                          ])
    end
  end

  describe "#errors_for" do
    let(:result) { described_class.failure([error1, error2]) }

    context "with symbol field name" do
      it "returns errors for that field" do
        errors = result.errors_for(:package)

        expect(errors.size).to eq(1)
        expect(errors.first).to eq(error1)
      end
    end

    context "with string field name" do
      it "returns errors for that field" do
        errors = result.errors_for("priority")

        expect(errors.size).to eq(1)
        expect(errors.first).to eq(error2)
      end
    end

    context "with non-existent field" do
      it "returns empty array" do
        errors = result.errors_for(:nonexistent)
        expect(errors).to be_empty
      end
    end

    context "with multiple errors for same field" do
      let(:error3) do
        Lutaml::Xml::Schema::Xsd::ValidationError.create(
          field: :package,
          message: "Package file does not exist",
        )
      end

      it "returns all errors for that field" do
        result = described_class.failure([error1, error3])
        errors = result.errors_for(:package)

        expect(errors.size).to eq(2)
        expect(errors).to include(error1, error3)
      end
    end
  end

  describe "#to_s" do
    context "for success result" do
      it "returns 'Valid'" do
        result = described_class.success
        expect(result.to_s).to eq("Valid")
      end
    end

    context "for failure result with single error" do
      it "formats with numbered list" do
        result = described_class.failure([error1])

        expect(result.to_s).to eq(
          "Validation failed with 1 error(s):\n  " \
          "1. package: Package path is required [constraint: presence]",
        )
      end
    end

    context "for failure result with multiple errors" do
      it "formats with numbered list" do
        result = described_class.failure([error1, error2])

        expect(result.to_s).to eq(
          "Validation failed with 2 error(s):\n  " \
          "1. package: Package path is required [constraint: presence]\n  " \
          "2. priority: Must be non-negative (value: -1) [constraint: >= 0]",
        )
      end
    end
  end

  describe "#validate!" do
    context "for valid result" do
      it "does not raise error" do
        result = described_class.success
        expect { result.validate! }.not_to raise_error
      end
    end

    context "for invalid result" do
      it "raises ValidationFailedError" do
        result = described_class.failure([error1])

        expect { result.validate! }.to raise_error(
          Lutaml::Xml::Schema::Xsd::ValidationFailedError,
        )
      end

      it "raises error with validation result" do
        result = described_class.failure([error1, error2])

        begin
          result.validate!
        rescue Lutaml::Xml::Schema::Xsd::ValidationFailedError => e
          expect(e.validation_result).to eq(result)
          expect(e.validation_result.error_count).to eq(2)
        end
      end
    end
  end

  describe "serialization" do
    let(:result) { described_class.failure([error1, error2]) }

    describe "#to_hash" do
      it "converts to hash with all fields" do
        hash = result.to_hash

        expect(hash["valid"]).to be false
        expect(hash["errors"]).to be_an(Array)
        expect(hash["errors"].size).to eq(2)
      end

      it "includes serialized errors" do
        hash = result.to_hash

        expect(hash["errors"].first["field"]).to eq("package")
        expect(hash["errors"].first["message"]).to eq(
          "Package path is required",
        )
      end
    end

    describe "YAML round-trip" do
      it "serializes and deserializes correctly" do
        yaml = result.to_yaml
        loaded = described_class.from_yaml(yaml)

        expect(loaded.valid?).to eq(result.valid?)
        expect(loaded.errors.size).to eq(result.errors.size)
        expect(loaded.errors.first.field).to eq(result.errors.first.field)
        expect(loaded.errors.first.message).to eq(
          result.errors.first.message,
        )
      end
    end

    describe "JSON round-trip" do
      it "serializes and deserializes correctly" do
        json = result.to_json
        loaded = described_class.from_json(json)

        expect(loaded.valid?).to eq(result.valid?)
        expect(loaded.errors.size).to eq(result.errors.size)
        expect(loaded.errors.first.field).to eq(result.errors.first.field)
      end
    end

    context "success result" do
      let(:success_result) { described_class.success }

      it "serializes as valid" do
        hash = success_result.to_hash

        expect(hash["valid"]).to be true
        # Lutaml::Model may serialize empty collections as nil or []
      end

      it "round-trips successfully" do
        yaml = success_result.to_yaml
        loaded = described_class.from_yaml(yaml)

        expect(loaded).to be_valid
        # errors may be nil or empty array after deserialization
        expect(loaded.errors || []).to be_empty
      end
    end
  end
end
