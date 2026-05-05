# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/validation_framework"

RSpec.describe Lutaml::Model::Validation::ValidationError do
  it "is a StandardError" do
    expect(described_class).to be < StandardError
  end

  it "stores message" do
    error = described_class.new("Something broke")
    expect(error.message).to eq("Something broke")
  end

  it "stores issues" do
    issue = Lutaml::Model::Validation::Issue.new(
      severity: "error", code: "E-001", message: "bad",
    )
    error = described_class.new("Failed", issues: [issue])
    expect(error.issues.length).to eq(1)
    expect(error.issues.first.code).to eq("E-001")
  end

  it "defaults issues to empty array" do
    error = described_class.new("Failed")
    expect(error.issues).to eq([])
  end
end
