# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/validation_framework"

RSpec.describe Lutaml::Model::Validation::Context do
  subject(:context) { described_class.new }

  it "starts with empty errors" do
    expect(context.errors).to be_empty
  end

  describe "#add_error" do
    it "accumulates errors" do
      issue = Lutaml::Model::Validation::Issue.new(
        severity: "error", code: "T-001", message: "bad",
      )
      context.add_error(issue)
      expect(context.errors.length).to eq(1)
      expect(context.errors.first).to eq(issue)
    end
  end

  describe "#add_errors" do
    it "concatenates multiple errors" do
      issues = Array.new(2) do |i|
        Lutaml::Model::Validation::Issue.new(
          severity: "error", code: "T-#{i}", message: "bad #{i}",
        )
      end
      context.add_errors(issues)
      expect(context.errors.length).to eq(2)
    end
  end

  describe "#rule_state" do
    it "provides per-rule state hash" do
      state = context.rule_state("R-001")
      state[:count] = 5
      expect(context.rule_state("R-001")[:count]).to eq(5)
    end

    it "isolates state between rules" do
      context.rule_state("R-001")[:val] = "a"
      context.rule_state("R-002")[:val] = "b"
      expect(context.rule_state("R-001")[:val]).to eq("a")
      expect(context.rule_state("R-002")[:val]).to eq("b")
    end
  end

  describe "#reset!" do
    it "clears errors and state" do
      context.add_error(double("issue"))
      context.rule_state("R")[:x] = 1
      context.reset!
      expect(context.errors).to be_empty
      expect(context.rule_state("R")).to be_empty
    end
  end
end
