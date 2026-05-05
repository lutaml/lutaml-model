# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/validation_framework"

RSpec.describe Lutaml::Model::Validation::LayerResult do
  subject(:layer) do
    described_class.new(
      name: "Structure",
      status: "fail",
      duration_ms: 15,
      issues: [error_issue, warning_issue],
    )
  end

  let(:error_issue) do
    Lutaml::Model::Validation::Issue.new(
      severity: "error", code: "E-001", message: "bad",
    )
  end

  let(:warning_issue) do
    Lutaml::Model::Validation::Issue.new(
      severity: "warning", code: "W-001", message: "meh",
    )
  end

  it "serializes to JSON" do
    parsed = JSON.parse(layer.to_json)
    expect(parsed["name"]).to eq("Structure")
    expect(parsed["status"]).to eq("fail")
    expect(parsed["issues"].length).to eq(2)
  end

  describe "#pass? / #fail?" do
    it "checks status" do
      expect(layer).not_to be_pass
      expect(layer).to be_fail
    end

    it "returns true for pass status" do
      passing = described_class.new(name: "x", status: "pass")
      expect(passing).to be_pass
    end
  end

  describe "severity filtering via HasIssues" do
    it "filters errors" do
      expect(layer.errors.length).to eq(1)
      expect(layer.errors.first.code).to eq("E-001")
    end

    it "filters warnings" do
      expect(layer.warnings.length).to eq(1)
      expect(layer.warnings.first.code).to eq("W-001")
    end

    it "returns empty for infos" do
      expect(layer.infos).to be_empty
    end

    it "returns empty for notices" do
      expect(layer.notices).to be_empty
    end
  end
end
