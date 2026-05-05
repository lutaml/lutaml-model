# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/validation_framework"

RSpec.describe Lutaml::Model::Validation::Issue do
  subject(:issue) do
    described_class.new(
      severity: "error",
      code: "TEST-001",
      message: "Something is wrong",
      location: "file.xml",
      line: 42,
      suggestion: "Fix it",
    )
  end

  describe "SEVERITIES constant" do
    it "defines allowed severity levels" do
      expect(described_class::SEVERITIES).to eq(%w[error warning info notice])
    end
  end

  describe "severity validation" do
    it "accepts valid severities" do
      described_class::SEVERITIES.each do |sev|
        expect { described_class.new(severity: sev, code: "T", message: "m") }
          .not_to raise_error
      end
    end

    it "rejects invalid severity" do
      expect do
        described_class.new(severity: "critical", code: "T", message: "m")
      end.to raise_error(ArgumentError, /Invalid severity: critical/)
    end

    it "allows nil severity" do
      expect { described_class.new(severity: nil, code: "T", message: "m") }
        .not_to raise_error
    end
  end

  describe "serialization" do
    it "serializes to JSON" do
      parsed = JSON.parse(issue.to_json)
      expect(parsed["severity"]).to eq("error")
      expect(parsed["code"]).to eq("TEST-001")
      expect(parsed["message"]).to eq("Something is wrong")
      expect(parsed["location"]).to eq("file.xml")
      expect(parsed["line"]).to eq(42)
      expect(parsed["suggestion"]).to eq("Fix it")
    end

    it "round-trips through JSON" do
      restored = described_class.from_json(issue.to_json)
      expect(restored.code).to eq("TEST-001")
      expect(restored.message).to eq("Something is wrong")
    end
  end

  describe "severity predicates" do
    it "returns correct predicate for error" do
      expect(issue).to be_error
      expect(issue).not_to be_warning
      expect(issue).not_to be_info
      expect(issue).not_to be_notice
    end

    it "returns correct predicate for warning" do
      warning = described_class.new(severity: "warning", code: "W",
                                    message: "m")
      expect(warning).to be_warning
      expect(warning).not_to be_error
    end
  end
end
