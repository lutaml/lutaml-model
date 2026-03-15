# frozen_string_literal: true

require_relative "spec_helper"
require "lutaml/xml/schema/xsd/namespace_uri_remapping"

RSpec.describe Lutaml::Xml::Schema::Xsd::NamespaceUriRemapping do
  describe "#validate" do
    context "with valid URIs" do
      it "returns success result" do
        remapping = described_class.new(
          from_uri: "http://example.com/old",
          to_uri: "http://example.com/new",
        )

        result = remapping.validate

        expect(result).to be_valid
        expect(result.errors).to be_empty
      end
    end

    context "when from_uri is missing" do
      it "returns failure result with error" do
        remapping = described_class.new(
          from_uri: nil,
          to_uri: "http://example.com/new",
        )

        result = remapping.validate

        expect(result).to be_invalid
        expect(result.error_count).to eq(1)
        expect(result.errors.first.field).to eq("from_uri")
        expect(result.errors.first.message).to eq("Source URI is required")
        expect(result.errors.first.constraint).to eq("presence")
      end
    end

    context "when from_uri is empty" do
      it "returns failure result with error" do
        remapping = described_class.new(
          from_uri: "",
          to_uri: "http://example.com/new",
        )

        result = remapping.validate

        expect(result).to be_invalid
        expect(result.errors_for(:from_uri).size).to eq(1)
      end
    end

    context "when to_uri is missing" do
      it "returns failure result with error" do
        remapping = described_class.new(
          from_uri: "http://example.com/old",
          to_uri: nil,
        )

        result = remapping.validate

        expect(result).to be_invalid
        expect(result.error_count).to eq(1)
        expect(result.errors.first.field).to eq("to_uri")
        expect(result.errors.first.message).to eq("Target URI is required")
      end
    end

    context "when to_uri is empty" do
      it "returns failure result with error" do
        remapping = described_class.new(
          from_uri: "http://example.com/old",
          to_uri: "",
        )

        result = remapping.validate

        expect(result).to be_invalid
        expect(result.errors_for(:to_uri).size).to eq(1)
      end
    end

    context "when from_uri equals to_uri" do
      it "returns failure result with error" do
        remapping = described_class.new(
          from_uri: "http://example.com/same",
          to_uri: "http://example.com/same",
        )

        result = remapping.validate

        expect(result).to be_invalid
        expect(result.error_count).to eq(1)
        expect(result.errors.first.field).to eq("to_uri")
        expect(result.errors.first.message).to eq(
          "Target URI must be different from source URI",
        )
        expect(result.errors.first.value).to eq("http://example.com/same")
        expect(result.errors.first.constraint).to eq("!= from_uri")
      end
    end

    context "with multiple validation errors" do
      it "returns all errors" do
        remapping = described_class.new(
          from_uri: nil,
          to_uri: nil,
        )

        result = remapping.validate

        expect(result).to be_invalid
        expect(result.error_count).to eq(2)
        expect(result.errors_for(:from_uri).size).to eq(1)
        expect(result.errors_for(:to_uri).size).to eq(1)
      end
    end
  end

  describe "#valid?" do
    it "returns true for valid remapping" do
      remapping = described_class.new(
        from_uri: "http://example.com/old",
        to_uri: "http://example.com/new",
      )

      expect(remapping).to be_valid
    end

    it "returns false for invalid remapping" do
      remapping = described_class.new(
        from_uri: nil,
        to_uri: "http://example.com/new",
      )

      expect(remapping).not_to be_valid
    end
  end

  describe "#validate!" do
    context "when valid" do
      it "does not raise error" do
        remapping = described_class.new(
          from_uri: "http://example.com/old",
          to_uri: "http://example.com/new",
        )

        expect { remapping.validate! }.not_to raise_error
      end
    end

    context "when invalid" do
      it "raises ValidationFailedError" do
        remapping = described_class.new(
          from_uri: nil,
          to_uri: "http://example.com/new",
        )

        expect { remapping.validate! }.to raise_error(
          Lutaml::Xml::Schema::Xsd::ValidationFailedError,
        )
      end

      it "includes validation result in error" do
        remapping = described_class.new(
          from_uri: nil,
          to_uri: nil,
        )

        begin
          remapping.validate!
        rescue Lutaml::Xml::Schema::Xsd::ValidationFailedError => e
          expect(e.validation_result.error_count).to eq(2)
        end
      end
    end
  end

  describe "#apply" do
    let(:remapping) do
      described_class.new(
        from_uri: "http://example.com/old",
        to_uri: "http://example.com/new",
      )
    end

    context "when URI matches from_uri" do
      it "returns to_uri" do
        result = remapping.apply("http://example.com/old")
        expect(result).to eq("http://example.com/new")
      end
    end

    context "when URI does not match from_uri" do
      it "returns original URI" do
        result = remapping.apply("http://example.com/other")
        expect(result).to eq("http://example.com/other")
      end
    end

    context "when URI is nil" do
      it "returns nil" do
        result = remapping.apply(nil)
        expect(result).to be_nil
      end
    end
  end

  describe "serialization" do
    let(:remapping) do
      described_class.new(
        from_uri: "http://example.com/old",
        to_uri: "http://example.com/new",
      )
    end

    describe "#to_hash" do
      it "converts to hash with all fields" do
        hash = remapping.to_hash

        expect(hash["from_uri"]).to eq("http://example.com/old")
        expect(hash["to_uri"]).to eq("http://example.com/new")
      end
    end

    describe "YAML round-trip" do
      it "serializes and deserializes correctly" do
        yaml = remapping.to_yaml
        loaded = described_class.from_yaml(yaml)

        expect(loaded.from_uri).to eq(remapping.from_uri)
        expect(loaded.to_uri).to eq(remapping.to_uri)
      end
    end

    describe "JSON round-trip" do
      it "serializes and deserializes correctly" do
        json = remapping.to_json
        loaded = described_class.from_json(json)

        expect(loaded.from_uri).to eq(remapping.from_uri)
        expect(loaded.to_uri).to eq(remapping.to_uri)
      end
    end
  end
end
