# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/validation_framework"

RSpec.describe Lutaml::Model::Validation::RemediationResult do
  it "serializes to JSON" do
    result = described_class.new(
      success: true,
      message: "Fixed",
      fixed_codes: ["DOC-020", "DOC-030"],
    )
    parsed = JSON.parse(result.to_json)
    expect(parsed["success"]).to be true
    expect(parsed["message"]).to eq("Fixed")
    expect(parsed["fixed_codes"]).to eq(["DOC-020", "DOC-030"])
  end

  it "defaults fixed_codes to nil when not provided" do
    result = described_class.new(success: false, message: "nope")
    expect(result.fixed_codes).to be_nil
  end
end
