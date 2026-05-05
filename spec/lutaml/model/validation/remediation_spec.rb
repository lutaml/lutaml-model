# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/validation_framework"

RSpec.describe Lutaml::Model::Validation::Remediation do
  subject(:remediation) { described_class.new }

  it "returns nil id by default" do
    expect(remediation.id).to be_nil
  end

  it "returns nil targets by default" do
    expect(remediation.targets).to be_nil
  end

  it "is always applicable" do
    expect(remediation.applicable?(nil, nil)).to be true
  end

  it "returns unsuccessful result from fix" do
    result = remediation.fix(nil, nil)
    expect(result).to be_a(Lutaml::Model::Validation::RemediationResult)
    expect(result.success).to be(false)
    expect(result.message).to eq("Not implemented")
  end

  it "returns nil preview by default" do
    expect(remediation.preview(nil, nil)).to be_nil
  end

  describe "custom subclass" do
    let(:custom_remediation) do
      Class.new(described_class) do
        def id = "REM-001"
        def targets = ["DOC-020"]

        def applicable?(_context, report)
          report.any? { |i| i.code == "DOC-020" }
        end

        def fix(_context, _report)
          Lutaml::Model::Validation::RemediationResult.new(
            success: true,
            message: "Fixed DOC-020",
            fixed_codes: ["DOC-020"],
          )
        end
      end
    end

    it "overrides id and targets" do
      rem = custom_remediation.new
      expect(rem.id).to eq("REM-001")
      expect(rem.targets).to eq(["DOC-020"])
    end

    it "checks applicability" do
      rem = custom_remediation.new
      issue = Lutaml::Model::Validation::Issue.new(
        severity: "error", code: "DOC-020", message: "bad",
      )
      expect(rem.applicable?(nil, [issue])).to be true
      expect(rem.applicable?(nil, [])).to be false
    end

    it "returns successful fix" do
      rem = custom_remediation.new
      result = rem.fix(nil, nil)
      expect(result.success).to be true
      expect(result.fixed_codes).to eq(["DOC-020"])
    end
  end
end
