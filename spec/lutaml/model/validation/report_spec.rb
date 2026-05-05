# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/validation_framework"

RSpec.describe Lutaml::Model::Validation::Report do
  subject(:report) do
    described_class.new(
      source: "test.xml",
      valid: false,
      duration_ms: 50,
      layers: [layer],
    )
  end

  let(:issue) do
    Lutaml::Model::Validation::Issue.new(
      severity: "error", code: "TEST-003", message: "Broken",
    )
  end

  let(:layer) do
    Lutaml::Model::Validation::LayerResult.new(
      name: "Check", status: "fail", issues: [issue],
    )
  end

  it "serializes to JSON" do
    parsed = JSON.parse(report.to_json)
    expect(parsed["source"]).to eq("test.xml")
    expect(parsed["valid"]).to be(false)
    expect(parsed["timestamp"]).not_to be_nil
  end

  it "auto-sets timestamp on initialization" do
    expect(report.timestamp).to match(/\d{4}-\d{2}-\d{2}T/)
  end

  describe "issue aggregation via HasIssues" do
    it "aggregates issues from all layers" do
      expect(report.issues.length).to eq(1)
    end

    it "filters errors" do
      expect(report.errors.length).to eq(1)
    end

    it "returns empty warnings when none present" do
      expect(report.warnings).to be_empty
    end
  end

  it "handles empty layers" do
    empty_report = described_class.new(source: "empty.xml", valid: true)
    expect(empty_report.issues).to be_empty
    expect(empty_report.errors).to be_empty
  end
end
