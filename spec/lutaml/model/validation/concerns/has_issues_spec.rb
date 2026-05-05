# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/validation_framework"

RSpec.describe Lutaml::Model::Validation::HasIssues do
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

  let(:info_issue) do
    Lutaml::Model::Validation::Issue.new(
      severity: "info", code: "I-001", message: "fyi",
    )
  end

  let(:notice_issue) do
    Lutaml::Model::Validation::Issue.new(
      severity: "notice", code: "N-001", message: "note",
    )
  end

  let(:container) do
    all_issues = [error_issue, warning_issue, info_issue, notice_issue]
    klass = Class.new do
      include Lutaml::Model::Validation::HasIssues

      attr_reader :issues

      def initialize(issues)
        @issues = issues
      end
    end
    klass.new(all_issues)
  end

  it "filters errors" do
    expect(container.errors).to eq([error_issue])
  end

  it "filters warnings" do
    expect(container.warnings).to eq([warning_issue])
  end

  it "filters infos" do
    expect(container.infos).to eq([info_issue])
  end

  it "filters notices" do
    expect(container.notices).to eq([notice_issue])
  end

  it "returns empty arrays when no matching severity" do
    only_errors = Class.new do
      include Lutaml::Model::Validation::HasIssues

      def issues
        [Lutaml::Model::Validation::Issue.new(
          severity: "error", code: "X", message: "y",
        )]
      end
    end.new

    expect(only_errors.warnings).to be_empty
    expect(only_errors.infos).to be_empty
    expect(only_errors.notices).to be_empty
  end
end
