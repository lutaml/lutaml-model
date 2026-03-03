# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Lutaml::Xml::Schema::Xsd::ValidationError do
  describe ".create" do
    context "with all parameters" do
      it "creates error with all fields" do
        error = described_class.create(
          field: :package,
          message: "Package path is required",
          value: "",
          constraint: "presence",
        )

        expect(error.field).to eq("package")
        expect(error.message).to eq("Package path is required")
        expect(error.value).to eq("")
        expect(error.constraint).to eq("presence")
      end
    end

    context "with symbol field name" do
      it "converts symbol to string" do
        error = described_class.create(
          field: :priority,
          message: "Must be positive",
        )

        expect(error.field).to eq("priority")
      end
    end

    context "with numeric value" do
      it "converts value to string" do
        error = described_class.create(
          field: :priority,
          message: "Must be positive",
          value: -1,
        )

        expect(error.value).to eq("-1")
      end
    end

    context "without optional parameters" do
      it "creates error with nil value and constraint" do
        error = described_class.create(
          field: :package,
          message: "Package path is required",
        )

        expect(error.field).to eq("package")
        expect(error.message).to eq("Package path is required")
        expect(error.value).to be_nil
        expect(error.constraint).to be_nil
      end
    end
  end

  describe "#to_s" do
    context "with all fields" do
      it "formats as complete string" do
        error = described_class.create(
          field: :priority,
          message: "Must be non-negative",
          value: -1,
          constraint: ">= 0",
        )

        expect(error.to_s).to eq(
          "priority: Must be non-negative (value: -1) [constraint: >= 0]",
        )
      end
    end

    context "with only field and message" do
      it "formats as simple string" do
        error = described_class.create(
          field: :package,
          message: "Package path is required",
        )

        expect(error.to_s).to eq("package: Package path is required")
      end
    end

    context "with field, message, and value" do
      it "includes value but not constraint" do
        error = described_class.create(
          field: :conflict_resolution,
          message: "Invalid strategy",
          value: "unknown",
        )

        expect(error.to_s).to eq(
          "conflict_resolution: Invalid strategy (value: unknown)",
        )
      end
    end

    context "with field, message, and constraint" do
      it "includes constraint but not value" do
        error = described_class.create(
          field: :from_uri,
          message: "URI is required",
          constraint: "presence",
        )

        expect(error.to_s).to eq(
          "from_uri: URI is required [constraint: presence]",
        )
      end
    end
  end

  describe "serialization" do
    let(:error) do
      described_class.create(
        field: :priority,
        message: "Must be non-negative",
        value: -1,
        constraint: ">= 0",
      )
    end

    describe "#to_hash" do
      it "converts to hash with all fields" do
        hash = error.to_hash

        expect(hash["field"]).to eq("priority")
        expect(hash["message"]).to eq("Must be non-negative")
        expect(hash["value"]).to eq("-1")
        expect(hash["constraint"]).to eq(">= 0")
      end
    end

    describe "YAML round-trip" do
      it "serializes and deserializes correctly" do
        yaml = error.to_yaml
        loaded = described_class.from_yaml(yaml)

        expect(loaded.field).to eq(error.field)
        expect(loaded.message).to eq(error.message)
        expect(loaded.value).to eq(error.value)
        expect(loaded.constraint).to eq(error.constraint)
      end
    end

    describe "JSON round-trip" do
      it "serializes and deserializes correctly" do
        json = error.to_json
        loaded = described_class.from_json(json)

        expect(loaded.field).to eq(error.field)
        expect(loaded.message).to eq(error.message)
        expect(loaded.value).to eq(error.value)
        expect(loaded.constraint).to eq(error.constraint)
      end
    end

    context "with nil optional fields" do
      let(:minimal_error) do
        described_class.create(
          field: :package,
          message: "Required",
        )
      end

      it "serializes required fields only" do
        hash = minimal_error.to_hash

        expect(hash["field"]).to eq("package")
        expect(hash["message"]).to eq("Required")
        # Lutaml::Model doesn't serialize nil values by default
      end

      it "round-trips with nil fields" do
        yaml = minimal_error.to_yaml
        loaded = described_class.from_yaml(yaml)

        expect(loaded.field).to eq("package")
        expect(loaded.message).to eq("Required")
        expect(loaded.value).to be_nil
        expect(loaded.constraint).to be_nil
      end
    end
  end
end